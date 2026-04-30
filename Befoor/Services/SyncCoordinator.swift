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



    init() {}

    // MARK: Configuration

    func configure(with context: ModelContext) {
        modelContext = context
    }

    // MARK: Public API

    /// Full sync: detect 1:1 meetings, create/update people, schedule pre-meeting reminders.
    func performFullSync() async {
        guard let context = modelContext else {
            print("[Befoor] SyncCoordinator: no modelContext")
            return
        }
        guard calendarService.isAuthorized else {
            print("[Befoor] SyncCoordinator: calendar not authorized")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        // Fetch enabled detection keywords
        let keywords = fetchEnabledKeywords(context: context)
        guard !keywords.isEmpty else {
            print("[Befoor] SyncCoordinator: no enabled keywords")
            lastSyncDate = Date()
            return
        }
        print("[Befoor] SyncCoordinator: \(keywords.count) keywords active")

        // Clear old sync records so events can be re-evaluated on every sync.
        // This ensures that if detection logic improves (e.g. new title parsing),
        // previously missed events get another chance.
        clearSyncRecords(context: context)

        // Reset lastMeetingDate for all people so rescheduled events are reflected.
        // We'll recompute it below from the fresh calendar scan.
        resetMeetingDates(context: context)

        // Scan for 1:1 meetings in the next 7 days.
        // Run the calendar + contacts scan off the main actor so taps stay responsive.
        let now = Date()
        guard let endDate = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        let keywordStrings = keywords.map(\.keyword)
        let meetings = await Task.detached(priority: .userInitiated) {
            CalendarService.shared.scanForOneOnOnes(
                from: now,
                to: endDate,
                keywords: keywordStrings
            )
        }.value

        print("[Befoor] SyncCoordinator: found \(meetings.count) 1:1 meetings")
        for m in meetings {
            print("[Befoor]   → \"\(m.eventTitle)\" person=\"\(m.otherPersonName)\" email=\(m.otherPersonEmail ?? "nil")")
        }

        // Process each detected meeting
        for meeting in meetings {
            // Skip already-synced events
            if isAlreadySynced(eventIdentifier: meeting.eventIdentifier, context: context) {
                print("[Befoor]   Skipping already-synced: \(meeting.eventTitle)")
                continue
            }

            // Find or create the person
            let person = findOrCreatePerson(
                name: meeting.otherPersonName,
                email: meeting.otherPersonEmail,
                context: context
            )

            // Pick the nearest upcoming meeting, or most recent past meeting
            if let existing = person.lastMeetingDate {
                let existingIsFuture = existing > now
                let newIsFuture = meeting.startDate > now
                if newIsFuture && existingIsFuture {
                    // Both in the future — keep the sooner one
                    if meeting.startDate < existing {
                        person.lastMeetingDate = meeting.startDate
                    }
                } else if newIsFuture {
                    // New is future, existing is past — prefer the upcoming one
                    person.lastMeetingDate = meeting.startDate
                } else if !existingIsFuture {
                    // Both in the past — keep the more recent one
                    if meeting.startDate > existing {
                        person.lastMeetingDate = meeting.startDate
                    }
                }
                // else: existing is future, new is past — keep the future one
            } else {
                person.lastMeetingDate = meeting.startDate
            }

            // Record the sync
            let record = CalendarSyncRecord(
                eventIdentifier: meeting.eventIdentifier,
                eventTitle: meeting.eventTitle,
                eventDate: meeting.startDate,
                personName: meeting.otherPersonName
            )
            context.insert(record)

            await Task.yield()
        }

        try? context.save()
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

    private func isAlreadySynced(eventIdentifier: String, context: ModelContext) -> Bool {
        let id = eventIdentifier
        let descriptor = FetchDescriptor<CalendarSyncRecord>(
            predicate: #Predicate { $0.eventIdentifier == id }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Reset lastMeetingDate on all people so rescheduled events are picked up correctly.
    private func resetMeetingDates(context: ModelContext) {
        let descriptor = FetchDescriptor<Person>()
        if let people = try? context.fetch(descriptor) {
            for person in people {
                person.lastMeetingDate = nil
            }
        }
    }

    /// Clear all sync records so every sync re-evaluates all upcoming events.
    private func clearSyncRecords(context: ModelContext) {
        let descriptor = FetchDescriptor<CalendarSyncRecord>()
        if let records = try? context.fetch(descriptor) {
            for record in records {
                context.delete(record)
            }
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
