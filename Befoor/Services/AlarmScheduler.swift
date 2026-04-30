import Foundation
import EventKit
import SwiftData
import BackgroundTasks
import WidgetKit

// MARK: - AlarmScheduler

/// Central coordinator: reads the calendar, diffs against currently-tracked alarms,
/// then creates / updates / cancels local notifications as needed.
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

    private init() {
        calendar.onStoreChanged = { [weak self] in
            Task { await self?.sync() }
        }
    }

    // MARK: - Public API

    /// Full sync: clears all pending notifications, then reschedules from scratch.
    func sync() async {
        guard settings.isEnabled else {
            await cancelAll()
            return
        }
        guard calendar.isAuthorized else { return }

        syncInProgress = true
        defer { syncInProgress = false }

        // Clear everything before rescheduling so no stale notifications remain.
        notifications.cancelAll()
        store.removeAll()

        let events  = calendar.fetchUpcomingEvents(
            lookAheadDays: settings.lookAheadDays,
            selectedIdentifiers: settings.selectedCalendarIdentifiers
        )
        let filtered = filter(events)

        // Budget: 4 notifs/event when finalAlarm on (10×4=40), 3 when off (13×3=39).
        // Remaining slots reserved for 1note1 reminders (20) and snooze rescheduling (4).
        let maxEvents = settings.finalAlarmEnabled ? 10 : 13
        var playerEntries: [AlarmPlayer.Entry] = []

        for event in filtered.prefix(maxEvents) {
            guard event.startDate > Date() else { continue }
            await Task.yield()

            let idealFireDate = event.startDate.addingTimeInterval(
                -Double(settings.leadTimeMinutes) * 60
            )
            // If the lead-time window has already passed, fire in 3 seconds.
            let fireDate = idealFireDate > Date() ? idealFireDate : Date().addingTimeInterval(3)

            let notifID = "befoor_\(event.eventIdentifier)_\(Int(event.startDate.timeIntervalSince1970))"
            let calName = event.calendar?.title ?? "Calendar"

            // Check if this event has an associated 1:1 person
            let personName = lookUpPersonName(for: event)

            await notifications.scheduleAlarm(
                identifier:     notifID,
                eventTitle:     event.title ?? "Appointment",
                calendarName:   calName,
                fireDate:       fireDate,
                eventStartDate: event.startDate,
                sound:          settings.selectedSound,
                personName:     personName
            )

            store.upsert(TrackedAlarmModel(
                eventIdentifier:        event.eventIdentifier,
                notificationIdentifier: notifID,
                eventStartDate:         event.startDate,
                eventTitle:             event.title ?? "Appointment",
                calendarIdentifier:     event.calendar?.calendarIdentifier ?? ""
            ))

            // Build the list of dates when AlarmPlayer should fire audio,
            // based on the user's audible alerts preference.
            var fireDates: [Date] = []
            let now = Date()
            switch settings.audibleAlertsMode {
            case .firstAndLast:
                if fireDate > now { fireDates.append(fireDate) }
                if settings.finalAlarmEnabled, event.startDate > now { fireDates.append(event.startDate) }
            case .all:
                if fireDate > now { fireDates.append(fireDate) }
                let r1 = fireDate.addingTimeInterval(120)
                let r2 = fireDate.addingTimeInterval(240)
                if r1 > now { fireDates.append(r1) }
                if r2 > now { fireDates.append(r2) }
                if settings.finalAlarmEnabled, event.startDate > now { fireDates.append(event.startDate) }
            case .none:
                break
            }
            if !fireDates.isEmpty {
                playerEntries.append(AlarmPlayer.Entry(
                    identifier: notifID,
                    fireDates:  fireDates,
                    sound:      settings.selectedSound
                ))
            }
        }

        AlarmPlayer.shared.setSchedule(playerEntries)

        store.prunePast()
        scheduledCount = store.alarms.count
        lastSyncDate   = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Cancel every Befoor notification, clear the store, and stop AlarmPlayer.
    func cancelAll() async {
        notifications.cancelAll()
        store.removeAll()
        AlarmPlayer.shared.setSchedule([])
        scheduledCount = 0
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

    /// Check if a calendar event corresponds to a synced 1:1 person.
    /// Looks up CalendarSyncRecord by event identifier, then finds the Person by name.
    private func lookUpPersonName(for event: EKEvent) -> String? {
        guard let context = modelContext else { return nil }

        let eventID = event.eventIdentifier ?? ""
        guard !eventID.isEmpty else { return nil }

        // Check if SyncCoordinator has recorded this event as a 1:1
        let syncDescriptor = FetchDescriptor<CalendarSyncRecord>(
            predicate: #Predicate { $0.eventIdentifier == eventID }
        )
        guard let record = try? context.fetch(syncDescriptor).first,
              let personName = record.personName, !personName.isEmpty else {
            return nil
        }

        // Verify the Person exists
        let nameQuery = personName
        let personDescriptor = FetchDescriptor<Person>(
            predicate: #Predicate { $0.name == nameQuery }
        )
        if (try? context.fetchCount(personDescriptor)) ?? 0 > 0 {
            return personName
        }

        return nil
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
