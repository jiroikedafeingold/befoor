import Foundation
import EventKit
import SwiftData
import BackgroundTasks
import WidgetKit

// MARK: - AlarmScheduler

/// Central coordinator: reads the calendar and schedules a system alarm (AlarmKit)
/// before each meeting, falling back to local notifications when alarms are off.
@MainActor
final class AlarmScheduler: ObservableObject {
    static let shared = AlarmScheduler()

    private let calendar     = CalendarService.shared
    private let notifications = NotificationService.shared
    private let store        = TrackedAlarmsStore.shared
    private let settings     = AppSettings.shared

    /// Background task identifier — must match Info.plist BGTaskSchedulerPermittedIdentifiers
    static let bgTaskID = "com.befoor.calendar-refresh"

    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncInProgress = false
    @Published private(set) var scheduledCount = 0

    /// Set from ContentView so we can query Person records during sync.
    var modelContext: ModelContext?

    private static let throttleInterval: TimeInterval = 30

    /// How long to wait after a calendar change before resyncing, so a burst of
    /// EKEventStoreChanged notifications collapses into one sync.
    private static let storeChangeDebounce: TimeInterval = 5
    private var storeChangeSyncTask: Task<Void, Never>?

    /// Whether the last sync used AlarmKit. If that changes (alarms were just
    /// allowed, or Sound was switched), the next sync skips the throttle so the
    /// meeting alerts are rebuilt right away.
    private var lastSyncUsedAlarms: Bool?

    /// Fingerprint of the alarm set last written to the CloudKit snapshot in this
    /// process. Nil at launch so the first sync always publishes once.
    private var lastPublishedSignature: Set<String>?

    private init() {
        calendar.onStoreChanged = { [weak self] in
            self?.syncAfterStoreChange()
        }
    }

    /// Calendar changes arrive in bursts (an account sync can post dozens of
    /// EKEventStoreChanged notifications in a row). Wait a few seconds for the
    /// burst to finish, and if a sync ran very recently, wait out the throttle
    /// window instead of dropping the change.
    private func syncAfterStoreChange() {
        requestResync()
    }

    /// Resyncs shortly, collapsing repeated requests into one. Used for calendar
    /// changes and for settings that are baked into scheduled alarms.
    func requestResync() {
        storeChangeSyncTask?.cancel()
        var delay = Self.storeChangeDebounce
        if let last = lastSyncDate {
            delay = max(delay, Self.throttleInterval - Date().timeIntervalSince(last) + 1)
        }
        storeChangeSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    // MARK: - Public API

    /// Full sync: rebuilds the meeting alarms (or fallback notifications) from the calendar.
    /// On secondary devices, loads the alarm list from CloudKit instead of
    /// scanning the calendar.
    func sync() async {
        guard settings.isEnabled else {
            await cancelAll()
            return
        }

        if !settings.isMainDevice {
            return
        }

        guard calendar.isAuthorized else { return }

        let useAlarms = settings.soundEnabled && MeetingAlarms.shared.isAuthorized
        if let last = lastSyncDate,
           Date().timeIntervalSince(last) < Self.throttleInterval,
           lastSyncUsedAlarms == useAlarms {
            return
        }
        lastSyncUsedAlarms = useAlarms

        syncInProgress = true
        defer { syncInProgress = false }

        // sync() runs on every foreground, but the alarm set usually hasn't
        // moved. Snapshot it so the widget is only reloaded when it really
        // changed — each reload spawns the widget extension process.
        let previousSignature = alarmSignature()

        // Clear the pending queue before rescheduling so no stale notifications
        // remain. Delivered alerts are kept — they're tidied by age and per-event
        // rules below rather than wiped wholesale on every sync.
        notifications.cancelAllPending()
        notifications.tidyDeliveredNotifications()
        store.removeAll()

        settings.migrateCalendarSelectionIfNeeded(allCalendarIdentifiers: calendar.allCalendarIdentifiers)
        let events  = calendar.fetchUpcomingEvents(
            lookAheadDays: settings.lookAheadDays,
            excludedIdentifiers: settings.excludedCalendarIdentifiers
        )
        let filtered = filter(events)

        // Meetings ring as AlarmKit alarms, which play through silent mode and
        // Focus. With Sound off, or if alarms aren't allowed, Befoor falls back to
        // notifications, which follow the ringer switch.
        var alarmRequests: [MeetingAlarmRequest] = []

        // Notification budget (fallback): up to 3 per event, leaving room in the
        // iOS limit of 64 for 1:1 reminders (20) and snoozes.
        let maxEvents = 13
        let alertMinutes = settings.alertMinutes

        for event in filtered.prefix(maxEvents) {
            guard event.startDate > Date() else { continue }
            await Task.yield()

            let notifID = "befoor_\(event.eventIdentifier)_\(Int(event.startDate.timeIntervalSince1970))"
            let calName = event.calendar?.title ?? "Calendar"

            // Check if this event has an associated 1:1 person
            let personInfo = lookUpPersonInfo(for: event)

            store.upsert(TrackedAlarmModel(
                eventIdentifier:        event.eventIdentifier,
                notificationIdentifier: notifID,
                eventStartDate:         event.startDate,
                eventTitle:             event.title ?? "Appointment",
                calendarIdentifier:     event.calendar?.calendarIdentifier ?? ""
            ))

            // 1:1 meetings with a tracked person are handled by the People tab —
            // skip the alarm notification and sound so they don't double up.
            if personInfo != nil { continue }

            let alerts = Self.alertsToSchedule(minutes: alertMinutes, start: event.startDate)
            guard !alerts.isEmpty else { continue }

            guard useAlarms else {
                await notifications.scheduleAlerts(
                    identifier:     notifID,
                    eventTitle:     event.title ?? "Appointment",
                    calendarName:   calName,
                    // Notifications can't tell whether a missed alert already showed, so
                    // only future ones are scheduled (else every sync would re-alert).
                    alerts:         alerts.filter { $0.date > Date() }.map { (slot: $0.slot, date: $0.date, minutesBefore: $0.minutes) },
                    eventStartDate: event.startDate,
                    sound:          settings.selectedSound
                )
                continue
            }

            for alert in alerts {
                alarmRequests.append(MeetingAlarmRequest(
                    meetingKey:    notifID,
                    slot:          alert.slot,
                    minutesBefore: alert.minutes,
                    fireDate:      alert.date,
                    eventTitle:    event.title ?? "Appointment",
                    eventStart:    event.startDate,
                    calendarName:  calName,
                    location:      event.location?.isEmpty == false ? event.location : nil,
                    sound:         settings.selectedSound,
                    snoozeMinutes: settings.snoozeDurationMinutes
                ))
            }
        }

        if useAlarms {
            // Anything AlarmKit refused (for example over its alarm limit) still
            // gets a notification so the meeting isn't missed.
            let failed = await MeetingAlarms.shared.reconcile(alarmRequests)
            for (meetingKey, requests) in Dictionary(grouping: failed, by: \.meetingKey) {
                guard let first = requests.first else { continue }
                await notifications.scheduleAlerts(
                    identifier:     meetingKey,
                    eventTitle:     first.eventTitle,
                    calendarName:   first.calendarName,
                    alerts:         requests.filter { $0.fireDate > Date() }.map { (slot: $0.slot, date: $0.fireDate, minutesBefore: $0.minutesBefore) },
                    eventStartDate: first.eventStart,
                    sound:          first.sound
                )
            }
        } else {
            MeetingAlarms.shared.cancelAll()
        }

        store.prunePast()
        store.saveSnapshot()
        let signature = alarmSignature()
        // Publishing rewrites the CloudKit record, which costs a network export here
        // and a push plus import on every other device. Skip it when the alarm set
        // is identical to what this process last published.
        if let context = modelContext, signature != lastPublishedSignature {
            store.publishToCloudKit(context: context)
            lastPublishedSignature = signature
        }
        scheduledCount = store.alarms.count
        lastSyncDate   = Date()
        if signature != previousSignature {
            WidgetCenter.shared.reloadAllTimelines()
        }
        await MeetingLiveActivityManager.shared.refresh(fromSync: true)
    }

    /// The alerts to schedule for a meeting: one per configured alert time, slot 1
    /// being the earliest. If the meeting is already inside some of its alert
    /// times (it was just added, or Befoor hadn't run), only the most recent
    /// missed one is kept, so a late-found meeting rings once rather than
    /// firing every missed alert at the same moment.
    static func alertsToSchedule(minutes: [Int], start: Date) -> [(slot: Int, minutes: Int, date: Date)] {
        let now = Date()
        let all = minutes.enumerated().map { index, m in
            (slot: index + 1, minutes: m, date: start.addingTimeInterval(-Double(m) * 60))
        }
        let missed = all.filter { $0.date <= now }
        let upcoming = all.filter { $0.date > now }
        if let latestMissed = missed.last {
            return [latestMissed] + upcoming
        }
        return upcoming
    }

    /// Order-independent fingerprint of the tracked alarm set, used to decide
    /// whether the widget actually needs reloading.
    private func alarmSignature() -> Set<String> {
        Set(store.alarms.values.map {
            "\($0.eventIdentifier)|\($0.notificationIdentifier)|\($0.eventTitle)|\($0.calendarIdentifier)|\(Int($0.eventStartDate.timeIntervalSince1970))"
        })
    }

    /// Cancel every Befoor alarm and notification and clear the store.
    func cancelAll() async {
        notifications.cancelAll()
        MeetingAlarms.shared.cancelAll()
        store.removeAll()
        store.saveSnapshot()
        scheduledCount = 0
        await MeetingLiveActivityManager.shared.refresh(fromSync: true)
    }

    // MARK: - Background Task Registration

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AlarmScheduler.bgTaskID,
            using: nil
        ) { task in
            self.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }

    func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AlarmScheduler.bgTaskID)
        // Earliest fire date: now + check interval
        request.earliestBeginDate = Date(timeIntervalSinceNow:
            Double(settings.backgroundCheckIntervalMinutes) * 60
        )
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        scheduleNextBackgroundRefresh()

        let syncTask = Task {
            await sync()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }

    // MARK: - 1:1 Person Lookup

    struct PersonInfo {
        let name: String
        let followUps: [String]
        let notes: [String]
    }

    /// Check if a calendar event corresponds to a synced 1:1 person.
    /// Returns the person's name, active follow-ups, and relevant notes.
    func lookUpPersonInfo(for event: EKEvent) -> PersonInfo? {
        guard let context = modelContext else { return nil }

        let eventID = event.eventIdentifier ?? ""
        guard !eventID.isEmpty else { return nil }

        guard let personName = SyncRecordStore.shared.personName(forEventIdentifier: eventID),
              !personName.isEmpty else {
            return nil
        }

        let nameQuery = personName
        let personDescriptor = FetchDescriptor<Person>(
            predicate: #Predicate { $0.name == nameQuery }
        )
        guard let person = try? context.fetch(personDescriptor).first else {
            return nil
        }

        let activeFollowUps = (person.followUps ?? [])
            .filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(3)
            .map(\.text)

        let truncate: (String) -> String = { text in
            text.count > 80 ? String(text.prefix(77)) + "…" : text
        }

        var noteTexts: [String] = []

        let longTermNotes = (person.longTermNotes ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(2)
        for note in longTermNotes {
            noteTexts.append(truncate(note.text))
        }

        let globalDescriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.isGlobal == true },
            sortBy: [SortDescriptor(\Note.meetingDate, order: .reverse)]
        )
        if let globalNotes = try? context.fetch(globalDescriptor) {
            for note in globalNotes.prefix(2) {
                noteTexts.append(truncate(note.text))
            }
        }

        let recentMeetingNote = (person.notes ?? [])
            .filter { !$0.isGlobal }
            .sorted { $0.meetingDate > $1.meetingDate }
            .first
        if let note = recentMeetingNote {
            noteTexts.append(truncate(note.text))
        }

        return PersonInfo(
            name: personName,
            followUps: Array(activeFollowUps),
            notes: noteTexts
        )
    }

    // MARK: - Filtering

    private func filter(_ events: [EKEvent]) -> [EKEvent] {
        let weekendCalendar = Calendar.current
        return events.filter { event in
            let title = (event.title ?? "").lowercased()

            // Skip events matching ignored keywords
            for keyword in settings.ignoredKeywords {
                if title.contains(keyword.lowercased()) { return false }
            }

            // Skip all-day events (no specific start time)
            if event.isAllDay { return false }

            // Skip weekends if configured
            if settings.skipWeekends {
                let weekday = weekendCalendar.component(.weekday, from: event.startDate)
                if weekday == 1 || weekday == 7 { return false }  // Sun=1, Sat=7
            }

            return true
        }
    }
}
