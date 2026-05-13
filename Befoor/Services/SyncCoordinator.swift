import Foundation
import SwiftData
import Observation

/// Coordinates syncing 1:1 meetings from the calendar into SwiftData (people, notes, reminders).
@Observable
@MainActor
final class SyncCoordinator {
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?

    private var modelContext: ModelContext?
    private let calendarService = CalendarService.shared
    private let notificationService = NotificationService.shared

    private static let throttleInterval: TimeInterval = 120

    init() {}

    // MARK: Configuration

    func configure(with context: ModelContext) {
        modelContext = context
        deduplicatePeople(context: context)
        backfillPersonIDs(context: context)
    }

    // MARK: Public API

    /// Full sync: detect 1:1 meetings, create/update people, schedule pre-meeting reminders.
    /// Only the main device scans the calendar. Non-main devices just deduplicate.
    /// - Parameter force: When true, clears sync records and re-evaluates all events.
    ///   When false, skips already-synced events and respects the throttle interval.
    func performFullSync(force: Bool = false) async {
        guard let context = modelContext else {
            print("[Befoor] SyncCoordinator: no modelContext")
            return
        }

        if !force, let last = lastSyncDate,
           Date().timeIntervalSince(last) < Self.throttleInterval {
            print("[Befoor] SyncCoordinator: throttled (last sync \(Int(Date().timeIntervalSince(last)))s ago)")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        deduplicatePeople(context: context)

        guard AppSettings.shared.isMainDevice else {
            print("[Befoor] SyncCoordinator: not the main device, skipping calendar sync")
            lastSyncDate = Date()
            return
        }

        guard calendarService.isAuthorized else {
            print("[Befoor] SyncCoordinator: calendar not authorized")
            return
        }

        let keywords = fetchEnabledKeywords(context: context)
        guard !keywords.isEmpty else {
            print("[Befoor] SyncCoordinator: no enabled keywords")
            lastSyncDate = Date()
            return
        }
        print("[Befoor] SyncCoordinator: \(keywords.count) keywords active, force=\(force)")

        let syncRecords = SyncRecordStore.shared
        if force {
            syncRecords.clearAll()
        } else {
            syncRecords.clearPast()
        }

        let now = Date()
        guard let endDate = Calendar.current.date(byAdding: .day, value: 35, to: now) else { return }
        let keywordStrings = keywords.map(\.keyword)
        let meetings = await Task.detached(priority: .userInitiated) {
            CalendarService.shared.scanForOneOnOnes(
                from: now,
                to: endDate,
                keywords: keywordStrings
            )
        }.value

        print("[Befoor] SyncCoordinator: found \(meetings.count) 1:1 meetings")

        var didModifyCloudRecords = false
        for meeting in meetings {
            if syncRecords.isAlreadySynced(eventIdentifier: meeting.eventIdentifier) {
                continue
            }

            let person = findOrCreatePerson(
                name: meeting.otherPersonName,
                email: meeting.otherPersonEmail,
                context: context
            )

            let bestDate: Date? = {
                guard let existing = person.lastMeetingDate else { return meeting.startDate }
                let existingIsFuture = existing > now
                let newIsFuture = meeting.startDate > now
                if newIsFuture && existingIsFuture {
                    return meeting.startDate < existing ? meeting.startDate : nil
                } else if newIsFuture {
                    return meeting.startDate
                } else if !existingIsFuture && meeting.startDate > existing {
                    return meeting.startDate
                }
                return nil
            }()
            if let bestDate, !datesEffectivelyEqual(bestDate, person.lastMeetingDate) {
                person.lastMeetingDate = bestDate
                didModifyCloudRecords = true
                print("[Befoor]   Updated date for \(person.name)")
            }

            syncRecords.record(
                eventIdentifier: meeting.eventIdentifier,
                eventTitle: meeting.eventTitle,
                eventDate: meeting.startDate,
                personName: meeting.otherPersonName
            )

            await Task.yield()
        }

        if didModifyCloudRecords {
            try? context.save()
            print("[Befoor] SyncCoordinator: saved cloud record changes")
        }
        syncRecords.save()
        lastSyncDate = Date()
    }

    /// Seed default detection keywords for new users.
    func seedDefaultKeywords() {
        guard let context = modelContext else { return }

        // Fetch all existing keywords and deduplicate (CloudKit can't enforce uniqueness)
        let descriptor = FetchDescriptor<DetectionKeyword>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let deduped = deduplicateKeywords(existing, context: context)

        guard deduped.isEmpty else { return }

        let defaults = ["1:1", "1-1", "one on one", "1 on 1", "catch up", "check in", "sync"]
        for keyword in defaults {
            context.insert(DetectionKeyword(keyword: keyword))
        }
        try? context.save()
    }

    // MARK: Private Helpers

    /// Set personID on records that have a person relationship but nil personID.
    /// This backfills records created before personID was added, so CloudKit can
    /// sync the flat UUID even when the relationship doesn't resolve on the remote device.
    private func backfillPersonIDs(context: ModelContext) {
        var didUpdate = false

        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        for note in notes where note.personID == nil {
            guard let person = note.person else { continue }
            note.personID = person.id
            didUpdate = true
        }

        let followUps = (try? context.fetch(FetchDescriptor<FollowUp>())) ?? []
        for followUp in followUps where followUp.personID == nil {
            guard let person = followUp.person else { continue }
            followUp.personID = person.id
            didUpdate = true
        }

        let longTermNotes = (try? context.fetch(FetchDescriptor<LongTermNote>())) ?? []
        for note in longTermNotes where note.personID == nil {
            guard let person = note.person else { continue }
            note.personID = person.id
            didUpdate = true
        }

        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        for reminder in reminders where reminder.personID == nil {
            guard let person = reminder.person else { continue }
            reminder.personID = person.id
            didUpdate = true
        }

        if didUpdate {
            try? context.save()
            print("[Befoor] SyncCoordinator: backfilled personIDs")
        }
    }

    private func fetchEnabledKeywords(context: ModelContext) -> [DetectionKeyword] {
        let descriptor = FetchDescriptor<DetectionKeyword>(
            predicate: #Predicate { $0.isEnabled }
        )
        let results = (try? context.fetch(descriptor)) ?? []
        // Deduplicate in case CloudKit synced duplicates from another device
        return deduplicateKeywords(results, context: context)
    }

    /// Remove duplicate keywords (by text), keeping the oldest. Returns the deduplicated list.
    @discardableResult
    private func deduplicateKeywords(_ keywords: [DetectionKeyword], context: ModelContext) -> [DetectionKeyword] {
        var seen: [String: DetectionKeyword] = [:]
        var duplicates: [DetectionKeyword] = []
        for kw in keywords.sorted(by: { $0.createdAt < $1.createdAt }) {
            let lower = kw.keyword.lowercased()
            if seen[lower] == nil {
                seen[lower] = kw
            } else {
                duplicates.append(kw)
            }
        }
        for dup in duplicates {
            context.delete(dup)
        }
        if !duplicates.isEmpty {
            try? context.save()
        }
        return Array(seen.values)
    }

    /// Merge duplicate Person records that can arise from multi-device CloudKit sync.
    private func deduplicatePeople(context: ModelContext) {
        let descriptor = FetchDescriptor<Person>()
        guard let allPeople = try? context.fetch(descriptor), allPeople.count > 1 else { return }

        var grouped: [String: [Person]] = [:]
        for person in allPeople {
            let key = person.name.lowercased().trimmingCharacters(in: .whitespaces)
            grouped[key, default: []].append(person)
        }

        var didMerge = false
        for (_, group) in grouped where group.count > 1 {
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            let keeper = sorted[0]

            for duplicate in sorted.dropFirst() {
                for note in duplicate.notes ?? [] {
                    note.person = keeper
                }
                for followUp in duplicate.followUps ?? [] {
                    followUp.person = keeper
                }
                for longTermNote in duplicate.longTermNotes ?? [] {
                    longTermNote.person = keeper
                }
                for reminder in duplicate.reminders ?? [] {
                    reminder.person = keeper
                }
                if keeper.email == nil, let email = duplicate.email {
                    keeper.email = email
                }
                if let dupDate = duplicate.lastMeetingDate {
                    if let keeperDate = keeper.lastMeetingDate {
                        let now = Date()
                        let dupIsFuture = dupDate > now
                        let keeperIsFuture = keeperDate > now
                        if dupIsFuture && keeperIsFuture {
                            keeper.lastMeetingDate = min(dupDate, keeperDate)
                        } else if dupIsFuture {
                            keeper.lastMeetingDate = dupDate
                        }
                    } else {
                        keeper.lastMeetingDate = dupDate
                    }
                }
                context.delete(duplicate)
                didMerge = true
            }
        }

        if didMerge {
            try? context.save()
            print("[Befoor] SyncCoordinator: merged duplicate people")
        }
    }

    private func datesEffectivelyEqual(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case let (a?, b?): return abs(a.timeIntervalSince(b)) < 60
        case (nil, nil): return true
        default: return false
        }
    }

    private func findOrCreatePerson(name: String, email: String?, context: ModelContext) -> Person {
        // Try to find by email first, then by name
        if let email, !email.isEmpty {
            let emailQuery = email
            let descriptor = FetchDescriptor<Person>(
                predicate: #Predicate { $0.email == emailQuery }
            )
            if let existing = try? context.fetch(descriptor).first {
                // Update the name if the stored one looks like an email or is empty
                if existing.name.contains("@") || existing.name.isEmpty {
                    existing.name = name
                }
                return existing
            }
        }

        let nameQuery = name
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate { $0.name == nameQuery }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        // Create new person
        print("[Befoor] SyncCoordinator: creating person \"\(name)\" email=\(email ?? "nil")")
        let person = Person(name: name, email: email)
        context.insert(person)
        return person
    }
}
