import Foundation
import EventKit
import BackgroundTasks
import WidgetKit
import AppIntents

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
    /// Meetings whose alerts AlarmKit refused in the last sync (usually its alarm
    /// limit), so they only get notifications, which don't ring on silent.
    @Published private(set) var alarmFallbackCount = 0

    private static let throttleInterval: TimeInterval = 30

    /// How long to wait after a calendar change before resyncing, so a burst of
    /// EKEventStoreChanged notifications collapses into one sync.
    private static let storeChangeDebounce: TimeInterval = 5
    private var storeChangeSyncTask: Task<Void, Never>?

    /// Whether the last sync used AlarmKit. If that changes (alarms were just
    /// allowed, or Sound was switched), the next sync skips the throttle so the
    /// meeting alerts are rebuilt right away.
    private var lastSyncUsedAlarms: Bool?

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

    /// The sync in progress, if any. Syncs suspend while scheduling, so two
    /// started together (app launch and becoming active do) would each schedule
    /// every alarm, and AlarmKit keeps both copies: two rings and two alarm Live
    /// Activities per alert. A sync that starts while one runs waits for it instead.
    private var runningSync: Task<Void, Never>?

    /// Full sync: rebuilds the meeting alarms (or fallback notifications) from the calendar.
    /// - Parameter force: skip the 30-second throttle — for changes the person
    ///   just made (Sync Now, skipping a meeting) that must take effect right away.
    func sync(force: Bool = false) async {
        if let runningSync {
            await runningSync.value
            // That sync may have read the calendar before this change was made.
            guard force, self.runningSync == nil else { return }
        }
        let task = Task { await performSync(force: force) }
        runningSync = task
        await task.value
        runningSync = nil
    }

    private func performSync(force: Bool) async {
        guard settings.isEnabled else {
            await cancelAll()
            return
        }

        guard calendar.isAuthorized else { return }

        // Every device reads its own calendar and rings its own alarms.
        let useAlarms = settings.soundEnabled && MeetingAlarms.shared.isAuthorized
        if !force, let last = lastSyncDate,
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
        let linkChanges = LinkWatch.update(events: filtered, calendar: calendar, notifications: notifications)

        // Meetings ring as AlarmKit alarms, which play through silent mode and
        // Focus. With Sound off, or if alarms aren't allowed, Befoor falls back to
        // notifications, which follow the ringer switch.
        var alarmRequests: [MeetingAlarmRequest] = []

        // Alarms have no small budget, so every meeting in the look-ahead window
        // gets them (anything over AlarmKit's limit falls back to notifications).
        // The notification fallback keeps to 2 per meeting time within the iOS
        // limit of 64, leaving room for snoozes.
        let maxMeetingTimes = useAlarms ? 100 : 20

        // Meetings that start at the same time share one set of alerts.
        let byStart = Dictionary(grouping: filtered.filter { $0.startDate > Date() }, by: \.startDate)
            .sorted { $0.key < $1.key }

        for (start, events) in byStart.prefix(maxMeetingTimes) {
            await Task.yield()

            // Same order as the countdown, which sorts by title too.
            let all = events.sorted { ($0.title ?? Self.untitled) < ($1.title ?? Self.untitled) }
            let meetingKey = Self.meetingKey(start: start)

            // Skipped and paused meetings stay in the list (so they can be
            // un-skipped) but get no alerts.
            for event in all {
                store.upsert(TrackedAlarmModel(
                    eventIdentifier:        event.eventIdentifier,
                    notificationIdentifier: meetingKey,
                    eventStartDate:         event.startDate,
                    eventTitle:             event.title ?? Self.untitled,
                    calendarIdentifier:     event.calendar?.calendarIdentifier ?? "",
                    joinURL:                calendar.joinURL(for: event),
                    linkChange:             linkChanges[LinkWatch.key(event)],
                    isSkipped:              settings.isSkipped(eventIdentifier: event.eventIdentifier, start: event.startDate),
                    note:                   settings.note(eventIdentifier: event.eventIdentifier, start: event.startDate)
                ))
            }
            let events = all.filter {
                !settings.isSkipped(eventIdentifier: $0.eventIdentifier, start: $0.startDate)
                    && !settings.isPaused(at: $0.startDate)
            }
            guard !events.isEmpty else { continue }
            let linkChange = events.lazy.compactMap { linkChanges[LinkWatch.key($0)] }.first
            let notes = events.compactMap { settings.note(eventIdentifier: $0.eventIdentifier, start: $0.startDate) }
            let note = notes.isEmpty ? nil : notes.joined(separator: " · ")

            let title = Self.combinedTitle(events.map { $0.title ?? Self.untitled })
            let calName = events.first?.calendar?.title ?? String(localized: "Calendar")
            let location = events.compactMap(\.location).first { !$0.isEmpty }
            let joinURL = events.lazy.compactMap { self.calendar.joinURL(for: $0) }.first

            let alerts = Self.alertsToSchedule(minutes: settings.alertMinutes(start: start, eventIdentifiers: events.map(\.eventIdentifier)),
                                                  start: start)
            guard !alerts.isEmpty else { continue }

            guard useAlarms else {
                await notifications.scheduleAlerts(
                    identifier:     meetingKey,
                    eventTitle:     title,
                    calendarName:   calName,
                    // Notifications can't tell whether a missed alert already showed, so
                    // only future ones are scheduled (else every sync would re-alert).
                    alerts:         alerts.filter { $0.date > Date() }.map { (slot: $0.slot, date: $0.date, minutesBefore: $0.minutes) },
                    eventStartDate: start,
                    sound:          settings.selectedSound
                )
                continue
            }

            for alert in alerts {
                alarmRequests.append(MeetingAlarmRequest(
                    meetingKey:    meetingKey,
                    slot:          alert.slot,
                    minutesBefore: alert.minutes,
                    fireDate:      alert.date,
                    eventTitle:    title,
                    eventStart:    start,
                    calendarName:  calName,
                    calendarRGB:   MeetingLiveActivityManager.rgb(events.first?.calendar?.cgColor),
                    location:      location,
                    joinURL:       joinURL,
                    linkChange:    linkChange,
                    note:          note,
                    sound:         settings.selectedSound,
                    // Ringing during another meeting: vibrate first, sound after 15 s.
                    quiet:         Self.inAnotherMeeting(at: alert.date, start: start, events: filtered),
                    snoozeMinutes: settings.snoozeDurationMinutes
                ))
            }
        }

        if useAlarms {
            // Anything AlarmKit refused (for example over its alarm limit) still
            // gets a notification so the meeting isn't missed.
            let failed = await MeetingAlarms.shared.reconcile(alarmRequests)
            alarmFallbackCount = Set(failed.map(\.meetingKey)).count
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
            alarmFallbackCount = 0
        }

        await notifications.scheduleMorningSummaries(
            meetings: filtered.filter {
                !settings.isSkipped(eventIdentifier: $0.eventIdentifier, start: $0.startDate)
                    && !settings.isPaused(at: $0.startDate)
            }.map { (title: $0.title ?? Self.untitled, start: $0.startDate) },
            enabled: settings.isEnabled && settings.morningSummaryEnabled,
            minutesAfterMidnight: settings.morningSummaryMinutes
        )

        store.prunePast()
        store.saveSnapshot()
        let signature = alarmSignature()
        scheduledCount = store.alarms.count
        lastSyncDate   = Date()
        if signature != previousSignature {
            WidgetCenter.shared.reloadAllTimelines()
        }
        await MeetingLiveActivityManager.shared.refresh(fromSync: true)
    }

    /// Whether an alert at `date` lands while another meeting (one not starting
    /// at `start`) is under way — back to back, or overlapping.
    static func inAnotherMeeting(at date: Date, start: Date, events: [EKEvent]) -> Bool {
        events.contains { other in
            other.startDate != start && other.startDate <= date && other.endDate > date
        }
    }

    /// Title for an event that has none.
    nonisolated static var untitled: String { String(localized: "Appointment") }

    /// Meetings that start at the same time share one alarm, notification and
    /// countdown, all keyed by the start time.
    nonisolated static func meetingKey(start: Date) -> String {
        "befoor_\(Int(start.timeIntervalSince1970))"
    }

    /// "Standup", or "Standup and Design Review" for meetings at the same time.
    /// A title that appears twice (the same event in two calendars) is listed once.
    nonisolated static func combinedTitle(_ titles: [String]) -> String {
        var seen = Set<String>()
        return titles.filter { seen.insert($0).inserted }.formatted(.list(type: .and))
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
            "\($0.eventIdentifier)|\($0.notificationIdentifier)|\($0.eventTitle)|\($0.calendarIdentifier)|\(Int($0.eventStartDate.timeIntervalSince1970))|\($0.joinURL?.absoluteString ?? "")|\($0.isSkipped)|\($0.note ?? "")"
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

// MARK: - Link changes

/// Remembers each upcoming meeting's video-call link so a removed or changed
/// link can be flagged: organizers sometimes re-send an invite at the last
/// minute without it, and the alarm would otherwise point at the old call.
enum LinkWatch {
    /// Event key → last link seen ("" for none).
    private static let linksKey = "bf_meetingLinks"
    /// Event key → "removed" or "changed", kept until the meeting is over.
    private static let changesKey = "bf_meetingLinkChanges"
    /// Event keys whose change has already been notified.
    private static let notifiedKey = "bf_meetingLinkNotified"

    /// Changes this close to the start also get a notification.
    private static let notifyWithin: TimeInterval = 2 * 3600

    static func key(_ event: EKEvent) -> String {
        AppSettings.skipKey(eventIdentifier: event.eventIdentifier, start: event.startDate)
    }

    /// Compares each meeting's link with the last one seen and returns the
    /// meetings whose link was removed or changed (event key → change).
    @MainActor
    static func update(events: [EKEvent], calendar: CalendarService, notifications: NotificationService) -> [String: String] {
        let defaults = UserDefaults.standard
        var links = defaults.dictionary(forKey: linksKey) as? [String: String] ?? [:]
        var changes = defaults.dictionary(forKey: changesKey) as? [String: String] ?? [:]
        var notified = Set(defaults.stringArray(forKey: notifiedKey) ?? [])
        let now = Date()
        var current = Set<String>()

        for event in events where event.endDate > now {
            let key = key(event)
            current.insert(key)
            let link = calendar.joinURL(for: event)?.absoluteString ?? ""
            if let old = links[key], !old.isEmpty, old != link {
                changes[key] = link.isEmpty ? "removed" : "changed"
                notified.remove(key)          // a new change is worth a new notification
            }
            links[key] = link
            if let change = changes[key], !notified.contains(key),
               event.startDate.timeIntervalSince(now) < notifyWithin {
                notifications.notifyLinkChange(
                    identifier: key,
                    title: event.title ?? AlarmScheduler.untitled,
                    start: event.startDate,
                    removed: change == "removed"
                )
                notified.insert(key)
            }
        }

        // Forget meetings that are over or gone from the calendar.
        defaults.set(links.filter { current.contains($0.key) }, forKey: linksKey)
        let kept = changes.filter { current.contains($0.key) }
        defaults.set(kept, forKey: changesKey)
        defaults.set(Array(notified.intersection(current)), forKey: notifiedKey)
        return kept
    }
}

// MARK: - Shortcuts

/// Runs a calendar sync from Shortcuts. iOS doesn't wake Befoor when the
/// calendar changes, so a meeting added while it's closed only gets alarms at
/// the next background check. An automation (say, "When Calendar is closed")
/// running this catches it right away.
struct SyncCalendarIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Befoor"
    static let description = IntentDescription("Checks your calendars and updates Befoor's meeting alarms.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AlarmScheduler.shared.sync(force: true)
        return .result(dialog: "Befoor's alarms are up to date.")
    }
}

/// The next meeting that hasn't started, isn't skipped or paused, and (for
/// Join) has a video link. Syncs first so a just-launched app has meetings.
@MainActor
private func nextMeeting(withLink: Bool = false) async -> TrackedAlarmModel? {
    let store = TrackedAlarmsStore.shared
    if store.alarms.isEmpty { await AlarmScheduler.shared.sync() }
    let settings = AppSettings.shared
    let now = Date()
    return store.alarms.values
        .filter { $0.eventStartDate > now && !$0.isSkipped && !settings.isPaused(at: $0.eventStartDate) }
        .filter { !withLink || $0.joinURL != nil }
        .min { $0.eventStartDate < $1.eventStartDate }
}

private func timeText(_ date: Date) -> String {
    Calendar.current.isDateInToday(date)
        ? date.formatted(date: .omitted, time: .shortened)
        : date.formatted(.dateTime.weekday(.wide).hour().minute())
}

/// "When's my next meeting?"
struct NextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Meeting"
    static let description = IntentDescription("Tells you your next meeting and when it starts.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let meeting = await nextMeeting() else {
            return .result(dialog: "You have no upcoming meetings.")
        }
        return .result(dialog: "\(meeting.eventTitle), \(timeText(meeting.eventStartDate)).")
    }
}

/// "Skip my next meeting" — the same as Skip in the list.
struct SkipNextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Next Meeting"
    static let description = IntentDescription("Turns off the alarms for your next meeting on all your devices.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let meeting = await nextMeeting() else {
            return .result(dialog: "You have no upcoming meetings.")
        }
        await MainActor.run {
            AppSettings.shared.setSkipped(true, eventIdentifier: meeting.eventIdentifier, start: meeting.eventStartDate)
        }
        await AlarmScheduler.shared.sync(force: true)
        return .result(dialog: "Skipped \(meeting.eventTitle) at \(timeText(meeting.eventStartDate)).")
    }
}

/// "Join my next meeting" — opens the next meeting's video call.
struct JoinNextMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Join Next Meeting"
    static let description = IntentDescription("Opens the video call for your next meeting that has one.")

    func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
        guard let meeting = await nextMeeting(withLink: true), let url = meeting.joinURL else {
            return .result(dialog: "None of your upcoming meetings has a video link.")
        }
        return .result(opensIntent: OpenURLIntent(url), dialog: "Joining \(meeting.eventTitle).")
    }
}

/// Skip or Ring from the Home Screen widget. A Live Activity intent, so the
/// system runs it in Befoor rather than the widget extension.
///
/// IMPORTANT: a copy with the same name and parameters lives in
/// BeforeWidget/BeforeWidget.swift for the widget's buttons.
struct SetMeetingSkippedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Meeting"
    static let isDiscoverable = false

    @Parameter(title: "Meeting")
    var eventIdentifier: String

    @Parameter(title: "Start")
    var start: Date

    @Parameter(title: "Skipped")
    var skipped: Bool

    init() {}

    init(eventIdentifier: String, start: Date, skipped: Bool) {
        self.eventIdentifier = eventIdentifier
        self.start = start
        self.skipped = skipped
    }

    func perform() async throws -> some IntentResult {
        let id = eventIdentifier, start = start, skipped = skipped
        await MainActor.run { AppSettings.shared.setSkipped(skipped, eventIdentifier: id, start: start) }
        await AlarmScheduler.shared.sync(force: true)
        return .result()
    }
}

struct BefoorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextMeetingIntent(),
            phrases: ["When's my next meeting in \(.applicationName)", "What's my next \(.applicationName) meeting"],
            shortTitle: "Next Meeting",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: JoinNextMeetingIntent(),
            phrases: ["Join my next meeting with \(.applicationName)", "Join my next \(.applicationName) meeting"],
            shortTitle: "Join Next Meeting",
            systemImageName: "video"
        )
        AppShortcut(
            intent: SkipNextMeetingIntent(),
            phrases: ["Skip my next meeting in \(.applicationName)", "Skip my next \(.applicationName) meeting"],
            shortTitle: "Skip Next Meeting",
            systemImageName: "bell.slash"
        )
        AppShortcut(
            intent: SyncCalendarIntent(),
            phrases: ["Sync \(.applicationName)", "Update \(.applicationName) alarms"],
            shortTitle: "Sync Calendar",
            systemImageName: "arrow.clockwise"
        )
    }
}
