import UserNotifications
import Foundation
import CoreHaptics
import SwiftData
import UIKit

// MARK: - Action / Category identifiers

enum AlarmAction {
    static let snooze     = "BEFOOR_SNOOZE"
    static let dismiss    = "BEFOOR_DISMISS"
    static let viewPerson = "BEFOOR_VIEW_PERSON"
    static let category   = "BEFOOR_ALARM"
    /// Alarm category for 1:1 meetings — includes a "View Person" action
    static let personCategory = "BEFOOR_ALARM_PERSON"
}

enum ReminderAction {
    static let snooze1Day  = "REMINDER_SNOOZE_1"
    static let snooze3Days = "REMINDER_SNOOZE_3"
    static let snooze7Days = "REMINDER_SNOOZE_7"
    static let dismiss     = "REMINDER_DISMISS"
    static let category    = "PERSON_REMINDER"
}

// MARK: - NotificationService

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var hapticStopWork: DispatchWorkItem?
    private var hapticFallbackItems: [DispatchWorkItem] = []

    /// Set by BefoorApp so notification callbacks can access SwiftData.
    var modelContainer: ModelContainer?

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
        prepareHapticEngine()
    }

    // MARK: Authorization

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(
                options: [.alert, .sound, .timeSensitive]
            )
        } catch {
            return false
        }
    }

    func checkPermission() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: Category Registration

    func registerCategories() {
        // Alarm category
        let mins = AppSettings.shared.snoozeDurationMinutes
        let alarmSnooze = UNNotificationAction(
            identifier: AlarmAction.snooze,
            title: String(localized: "Snooze \(mins) min"),
            options: []
        )
        let alarmDismiss = UNNotificationAction(
            identifier: AlarmAction.dismiss,
            title: String(localized: "Dismiss"),
            options: [.destructive]
        )
        let alarmCategory = UNNotificationCategory(
            identifier: AlarmAction.category,
            actions: [alarmSnooze, alarmDismiss],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Alarm category for 1:1 meetings — adds a "View Person" action
        let viewPerson = UNNotificationAction(
            identifier: AlarmAction.viewPerson,
            title: String(localized: "View Person"),
            options: [.foreground]
        )
        let alarmPersonCategory = UNNotificationCategory(
            identifier: AlarmAction.personCategory,
            actions: [alarmSnooze, alarmDismiss, viewPerson],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Reminder category
        let snooze1 = UNNotificationAction(
            identifier: ReminderAction.snooze1Day,
            title: String(localized: "Snooze 1 Day"),
            options: []
        )
        let snooze3 = UNNotificationAction(
            identifier: ReminderAction.snooze3Days,
            title: String(localized: "Snooze 3 Days"),
            options: []
        )
        let snooze7 = UNNotificationAction(
            identifier: ReminderAction.snooze7Days,
            title: String(localized: "Snooze 7 Days"),
            options: []
        )
        let reminderDismiss = UNNotificationAction(
            identifier: ReminderAction.dismiss,
            title: String(localized: "Dismiss"),
            options: [.destructive]
        )
        let reminderCategory = UNNotificationCategory(
            identifier: ReminderAction.category,
            actions: [snooze1, snooze3, snooze7, reminderDismiss],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([alarmCategory, alarmPersonCategory, reminderCategory])
    }

    // MARK: Schedule

    /// Schedules a full alarm sequence: an initial ring plus two follow-up rings
    /// one and two minutes later, so the alarm persists until the user acts on it.
    /// Returns the primary notification identifier.
    @discardableResult
    func scheduleAlarm(
        identifier: String,
        eventTitle: String,
        calendarName: String,
        fireDate: Date,
        eventStartDate: Date,
        sound: BefoorSound,
        personName: String? = nil,
        followUps: [String]? = nil,
        notes: [String]? = nil
    ) async -> String {
        // Build time labels for each ring based on minutes until the event starts.
        let r1Date = fireDate.addingTimeInterval(120)
        let r2Date = fireDate.addingTimeInterval(240)

        func timeLabel(from ringDate: Date) -> String {
            let mins = Int(ceil(eventStartDate.timeIntervalSince(ringDate) / 60))
            if mins > 1  { return "in \(mins) minutes" }
            if mins == 1 { return "in 1 minute" }
            return "now"
        }

        var rings: [(id: String, date: Date, subtitle: String)] = [
            (
                id:       identifier,
                date:     fireDate,
                subtitle: "Starting \(timeLabel(from: fireDate))"
            ),
            (
                id:       identifier + "_r1",
                date:     r1Date,
                subtitle: "Starting \(timeLabel(from: r1Date))"
            ),
            (
                id:       identifier + "_r2",
                date:     r2Date,
                subtitle: "Starting \(timeLabel(from: r2Date))"
            ),
        ]

        // Final alarm fires at the exact event start time if it hasn't already passed
        // and the user has not explicitly dismissed the earlier reminders.
        if AppSettings.shared.finalAlarmEnabled, eventStartDate > Date() {
            rings.append((
                id:       identifier + "_final",
                date:     eventStartDate,
                subtitle: "Starting now"
            ))
        }

        for ring in rings {
            guard ring.date > Date() else { continue }
            await schedule(
                id:             ring.id,
                title:          eventTitle,
                subtitle:       ring.subtitle,
                calendarName:   calendarName,
                threadID:       identifier,
                date:           ring.date,
                sound:          sound,
                personName:     personName,
                followUps:      followUps,
                notes:          notes
            )
        }

        return identifier
    }

    // MARK: Cancel

    /// Cancels the primary notification and its follow-ups.
    func cancel(identifiers: [String]) {
        let withFollowUps = identifiers.flatMap {
            [$0, $0 + "_r1", $0 + "_r2", $0 + "_snooze", $0 + "_final"]
        }
        center.removePendingNotificationRequests(withIdentifiers: withFollowUps)
        center.removeDeliveredNotifications(withIdentifiers: withFollowUps)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// Cancel a single notification by identifier.
    func cancelNotification(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    // MARK: Reminder Scheduling

    /// Schedule a pre-meeting reminder notification for a 1:1 meeting.
    @discardableResult
    func schedulePreMeetingReminder(
        identifier: String,
        personName: String,
        meetingTitle: String,
        fireDate: Date
    ) async -> String {
        guard fireDate > Date() else { return identifier }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming 1:1 with \(personName)"
        content.subtitle = meetingTitle
        content.body = "Review your notes and follow-ups before the meeting."
        content.categoryIdentifier = ReminderAction.category
        content.threadIdentifier = "reminder_\(personName)"
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        content.userInfo = ["type": "preMeeting", "personName": personName]

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("[Befoor] Failed to schedule pre-meeting reminder \(identifier): \(error)")
        }

        return identifier
    }

    /// Schedule a general person reminder notification.
    @discardableResult
    func schedulePersonReminder(
        identifier: String,
        personName: String,
        title: String,
        fireDate: Date,
        personIDString: String
    ) async -> String {
        guard fireDate > Date() else { return identifier }

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = personName
        content.body = "Tap to view \(personName)'s details."
        content.categoryIdentifier = ReminderAction.category
        content.threadIdentifier = "reminder_\(personName)"
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        content.userInfo = [
            "type": "personReminder",
            "personName": personName,
            "personID": personIDString,
            "reminderID": identifier,
        ]

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("[Befoor] Failed to schedule person reminder \(identifier): \(error)")
        }

        return identifier
    }

    // MARK: Query

    func pendingIdentifiers() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        // Strip the _r1/_r2/_snooze suffixes so callers see only primary IDs
        return Set(requests.map {
            $0.identifier
                .replacingOccurrences(of: "_r1", with: "")
                .replacingOccurrences(of: "_r2", with: "")
                .replacingOccurrences(of: "_snooze", with: "")
                .replacingOccurrences(of: "_final", with: "")
        })
    }

    func clearBadge() {
        Task {
            try? await center.setBadgeCount(0)
        }
    }

    /// Remove delivered notifications older than the given interval so the
    /// notification center doesn't accumulate banners the user no longer cares about.
    func pruneStaleDeliveredNotifications(olderThan interval: TimeInterval = 30 * 60) {
        let cutoff = Date().addingTimeInterval(-interval)
        let center = self.center
        center.getDeliveredNotifications { delivered in
            let staleIDs = delivered
                .filter { $0.date < cutoff }
                .map(\.request.identifier)
            guard !staleIDs.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: staleIDs)
            print("[Befoor] Pruned \(staleIDs.count) delivered notification(s) older than \(Int(interval / 60)) min")
        }
    }

    /// Remove every delivered notification except the one with the given identifier.
    /// Used when a new notification is presented so the notification center only
    /// shows the most recent one and older banners don't pile up.
    private func clearDeliveredNotifications(except keepIdentifier: String) {
        let center = self.center
        center.getDeliveredNotifications { delivered in
            let staleIDs = delivered
                .map(\.request.identifier)
                .filter { $0 != keepIdentifier }
            guard !staleIDs.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: staleIDs)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show alarm as a banner even when the app is foregrounded.
    /// Routes by category: alarm → haptics + banner; reminder → banner + sound + list.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let category = notification.request.content.categoryIdentifier

        // Whenever a new notification is presented, clear out every older
        // delivered notification so the notification center only ever shows
        // the one the user is currently seeing.
        clearDeliveredNotifications(except: notification.request.identifier)

        if category == ReminderAction.category {
            // Person reminders: show banner, play sound, show in list
            completionHandler([.banner, .sound, .list])
            return
        }

        // Alarm notifications
        let id = notification.request.identifier
        let settings = AppSettings.shared
        let isAudible: Bool = {
            switch settings.audibleAlertsMode {
            case .all:          return true
            case .none:         return false
            case .firstAndLast:
                return !(id.hasSuffix("_r1") || id.hasSuffix("_r2"))
            }
        }()
        if settings.hapticsEnabled && isAudible { playAlarmHaptics() }
        completionHandler([.banner])
    }

    /// Handle Snooze / Dismiss tap — routes by category.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let notif = response.notification
        let category = notif.request.content.categoryIdentifier

        if category == ReminderAction.category {
            handleReminderResponse(response)
            return
        }

        guard category == AlarmAction.category || category == AlarmAction.personCategory else { return }

        // "View Person" action — navigate to the person and dismiss the alarm
        if response.actionIdentifier == AlarmAction.viewPerson {
            if let personName = response.notification.request.content.userInfo["personName"] as? String {
                navigateToPersonByName(personName)
            }
            let base = stripAlarmSuffix(response.notification.request.identifier)
            cancel(identifiers: [base])
            stopHaptics()
            Task { @MainActor in AlarmPlayer.shared.dismiss(identifier: base) }
            return
        }

        switch response.actionIdentifier {
        case AlarmAction.snooze:
            let base = stripAlarmSuffix(notif.request.identifier)
            snoozeAlarm(base: base, content: notif.request.content)

        case UNNotificationDefaultActionIdentifier:
            // Tapping the notification banner snoozes, and for person alarms also navigates.
            let base = stripAlarmSuffix(notif.request.identifier)
            snoozeAlarm(base: base, content: notif.request.content)
            if let personName = notif.request.content.userInfo["personName"] as? String {
                navigateToPersonByName(personName)
            }

        case AlarmAction.dismiss, UNNotificationDismissActionIdentifier:
            let base = stripAlarmSuffix(notif.request.identifier)
            cancel(identifiers: [base])
            stopHaptics()
            Task { @MainActor in AlarmPlayer.shared.dismiss(identifier: base) }

        default:
            break
        }
    }

    // MARK: Reminder Action Handling

    private func handleReminderResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        let personIDString = userInfo["personID"] as? String
        let reminderID = userInfo["reminderID"] as? String

        switch response.actionIdentifier {
        case ReminderAction.snooze1Day:
            rescheduleReminder(response: response, days: 1)

        case ReminderAction.snooze3Days:
            rescheduleReminder(response: response, days: 3)

        case ReminderAction.snooze7Days:
            rescheduleReminder(response: response, days: 7)

        case ReminderAction.dismiss, UNNotificationDismissActionIdentifier:
            // Mark reminder as completed in SwiftData
            if let reminderID {
                markReminderCompleted(notificationIdentifier: reminderID)
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification — navigate to person
            if let personIDString {
                NotificationCenter.default.post(
                    name: .navigateToPerson,
                    object: nil,
                    userInfo: ["personID": personIDString]
                )
            }

        default:
            break
        }
    }

    private func rescheduleReminder(response: UNNotificationResponse, days: Int) {
        let userInfo = response.notification.request.content.userInfo
        guard let personName = userInfo["personName"] as? String,
              let personIDString = userInfo["personID"] as? String,
              let reminderIDString = userInfo["reminderID"] as? String
        else { return }

        let newDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let newID = "reminder_\(UUID().uuidString)"
        let title = response.notification.request.content.title

        Task {
            await schedulePersonReminder(
                identifier: newID,
                personName: personName,
                title: title,
                fireDate: newDate,
                personIDString: personIDString
            )

            // Update the Reminder model in SwiftData
            updateReminderInStore(
                oldNotificationID: reminderIDString,
                newNotificationID: newID,
                newFireDate: newDate,
                snoozeDays: days
            )
        }
    }

    private func markReminderCompleted(notificationIdentifier: String) {
        guard let container = modelContainer else { return }
        Task { @MainActor in
            let context = ModelContext(container)
            let id = notificationIdentifier
            let descriptor = FetchDescriptor<Reminder>(
                predicate: #Predicate { $0.notificationIdentifier == id }
            )
            if let reminder = try? context.fetch(descriptor).first {
                reminder.isCompleted = true
                try? context.save()
            }
        }
    }

    private func updateReminderInStore(
        oldNotificationID: String,
        newNotificationID: String,
        newFireDate: Date,
        snoozeDays: Int
    ) {
        guard let container = modelContainer else { return }
        Task { @MainActor in
            let context = ModelContext(container)
            let id = oldNotificationID
            let descriptor = FetchDescriptor<Reminder>(
                predicate: #Predicate { $0.notificationIdentifier == id }
            )
            if let reminder = try? context.fetch(descriptor).first {
                reminder.notificationIdentifier = newNotificationID
                reminder.fireDate = newFireDate
                reminder.snoozeDays = snoozeDays
                try? context.save()
            }
        }
    }

    // MARK: Alarm Helpers

    private func stripAlarmSuffix(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_r1", with: "")
            .replacingOccurrences(of: "_r2", with: "")
            .replacingOccurrences(of: "_snooze", with: "")
            .replacingOccurrences(of: "_final", with: "")
    }

    private func snoozeAlarm(base: String, content: UNNotificationContent) {
        let followUps = [base + "_r1", base + "_r2", base + "_final"]
        center.removePendingNotificationRequests(withIdentifiers: followUps)

        let snoozeSeconds = Double(AppSettings.shared.snoozeDurationMinutes) * 60
        let snoozeID = base + "_snooze"

        let mutable = content.mutableCopy() as! UNMutableNotificationContent
        mutable.subtitle = "Snoozed reminder"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: snoozeSeconds,
            repeats: false
        )
        let request = UNNotificationRequest(identifier: snoozeID, content: mutable, trigger: trigger)
        center.add(request) { error in
            if let error { print("[Befoor] Snooze schedule failed: \(error)") }
        }

        stopHaptics()
        Task { @MainActor in
            AlarmPlayer.shared.stopForSnooze(identifier: base)
            let snoozeDate = Date().addingTimeInterval(snoozeSeconds)
            AlarmPlayer.shared.addSnooze(
                identifier: base,
                at:         snoozeDate,
                sound:      AppSettings.shared.selectedSound
            )
        }
    }

    /// Post a notification that navigates to a person by name.
    /// ContentView observes this and switches to the People tab, then pushes the person detail.
    private func navigateToPersonByName(_ personName: String) {
        NotificationCenter.default.post(
            name: .navigateToPerson,
            object: nil,
            userInfo: ["personName": personName]
        )
    }

    // MARK: Schedule helpers

    private func schedule(
        id: String,
        title: String,
        subtitle: String,
        calendarName: String,
        threadID: String,
        date: Date,
        sound: BefoorSound,
        personName: String? = nil,
        followUps: [String]? = nil,
        notes: [String]? = nil
    ) async {
        let content = UNMutableNotificationContent()
        content.title              = title
        content.subtitle           = subtitle
        if let personName {
            var bodyParts = ["1:1 with \(personName)  ·  \(calendarName)"]
            if let followUps, !followUps.isEmpty {
                bodyParts.append("Follow-ups:")
                for item in followUps {
                    bodyParts.append("• \(item)")
                }
            }
            if let notes, !notes.isEmpty {
                bodyParts.append("Notes:")
                for item in notes {
                    bodyParts.append("• \(item)")
                }
            }
            content.body = bodyParts.joined(separator: "\n")
        } else {
            content.body           = calendarName
        }
        content.threadIdentifier   = threadID
        content.summaryArgument    = title
        let settings = AppSettings.shared
        let isAudible: Bool = {
            switch settings.audibleAlertsMode {
            case .all:          return true
            case .none:         return false
            case .firstAndLast:
                let isMidAlert = id.hasSuffix("_r1") || id.hasSuffix("_r2")
                return !isMidAlert
            }
        }()
        content.sound              = (isAudible && settings.soundEnabled) ? sound.notificationSound : nil
        content.categoryIdentifier = personName != nil ? AlarmAction.personCategory : AlarmAction.category
        content.interruptionLevel  = .timeSensitive
        if let personName {
            content.userInfo["personName"] = personName
        }

        // Clear previously delivered notifications for this event thread
        // so the notification center doesn't pile up stale banners.
        center.removeDeliveredNotifications(withIdentifiers: [threadID, threadID + "_r1", threadID + "_r2", threadID + "_final", threadID + "_snooze"])

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("[Befoor] Failed to schedule \(id): \(error)")
        }
    }

    // MARK: Haptics

    private func prepareHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
            hapticEngine?.stoppedHandler = { _ in }
            try hapticEngine?.start()
        } catch {
            print("[Befoor] Haptic engine error: \(error)")
        }
    }

    /// Plays a repeating thud-thud-thud pattern to feel like an alarm.
    func playAlarmHaptics() {
        stopHaptics()  // cancel any previous sequence first

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else {
            #if !targetEnvironment(macCatalyst)
            // Fallback: UIKit impact pulses stored as cancellable work items
            DispatchQueue.main.async {
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.prepare()
                let baseOffsets: [Double] = [0.00, 0.14, 0.28, 0.42, 0.97, 1.11, 1.25, 1.39, 1.94, 2.08, 2.22, 2.36, 2.91, 3.05, 3.19, 3.33]
                let loopDuration = 4.0
                for loop in 0..<6 {
                    for offset in baseOffsets {
                        let t = Double(loop) * loopDuration + offset
                        let item = DispatchWorkItem { gen.impactOccurred(intensity: 1.0) }
                        self.hapticFallbackItems.append(item)
                        DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: item)
                    }
                }
            }
            #endif
            return
        }

        // One loop: 4 groups of 4 rapid thumps, tightly spaced for maximum impact.
        // Each group fires at 0.14 s intervals; groups are separated by 0.55 s gaps.
        // The advanced player loops continuously for 25 seconds.
        var events: [CHHapticEvent] = []
        let times: [TimeInterval] = [
            0.00, 0.14, 0.28, 0.42,   // group 1
            0.97, 1.11, 1.25, 1.39,   // group 2
            1.94, 2.08, 2.22, 2.36,   // group 3
            2.91, 3.05, 3.19, 3.33,   // group 4
        ]
        let loopDuration: TimeInterval = 4.0

        for t in times {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: t,
                duration: 0.20
            ))
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: t
            ))
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player  = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd     = loopDuration
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
            hapticPlayer = player

            let stopWork = DispatchWorkItem { [weak self] in
                try? self?.hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
                self?.hapticPlayer = nil
            }
            hapticStopWork = stopWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: stopWork)
        } catch {
            print("[Befoor] Haptic playback error: \(error)")
        }
    }

    private func stopHaptics() {
        // Cancel the CHHaptic player
        hapticStopWork?.cancel()
        hapticStopWork = nil
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        hapticPlayer = nil

        // Cancel any queued UIKit fallback pulses
        hapticFallbackItems.forEach { $0.cancel() }
        hapticFallbackItems.removeAll()
    }
}
