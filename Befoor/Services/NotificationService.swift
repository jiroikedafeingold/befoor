import UserNotifications
import Foundation
import SwiftData

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

    /// Set by BefoorApp so notification callbacks can access SwiftData.
    var modelContainer: ModelContainer?

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
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

    /// Schedules notification alerts for a meeting, one per configured alert
    /// time. Used when meeting alarms can't go through AlarmKit (Sound off, or
    /// alarms not allowed). Slot 1 uses the meeting identifier itself; slots 2
    /// and 3 add the "_r1"/"_r2" suffixes the rest of this service understands.
    @discardableResult
    func scheduleAlerts(
        identifier: String,
        eventTitle: String,
        calendarName: String,
        alerts: [(slot: Int, date: Date, minutesBefore: Int)],
        eventStartDate: Date,
        sound: BefoorSound,
        personName: String? = nil,
        followUps: [String]? = nil,
        notes: [String]? = nil
    ) async -> String {
        for alert in alerts where alert.date > Date() {
            let id = alert.slot <= 1 ? identifier : identifier + "_r\(alert.slot - 1)"
            let subtitle: String
            switch alert.minutesBefore {
            case 0:  subtitle = "Starting now"
            case 1:  subtitle = "Starting in 1 minute"
            default: subtitle = "Starting in \(alert.minutesBefore) minutes"
            }
            await schedule(
                id:             id,
                title:          eventTitle,
                subtitle:       subtitle,
                calendarName:   calendarName,
                threadID:       identifier,
                date:           alert.date,
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

    /// Clears everything still scheduled but leaves already-delivered alerts alone.
    /// Used by a resync, which rebuilds the pending queue from scratch and must not
    /// discard alerts the user hasn't acted on yet.
    func cancelAllPending() {
        center.removeAllPendingNotificationRequests()
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

    /// Delivered notifications older than this are cleared automatically.
    static let deliveredRetention: TimeInterval = 30 * 60

    /// Keeps Notification Center down to a single Befoor notification:
    /// - only the most recently delivered one is kept, so a newer alert (for the
    ///   same meeting or a new one) clears out everything before it, and
    /// - even that one is removed once it's more than 30 minutes old.
    ///
    /// iOS gives an app no hook when a notification arrives in the background, so
    /// this runs whenever Befoor gets a chance: when an alert is presented in the
    /// foreground, when the app opens, on every sync (including background
    /// refresh and alarm Stop/Snooze), and when a notification is acted on.
    func tidyDeliveredNotifications() {
        let center = self.center
        let cutoff = Date().addingTimeInterval(-Self.deliveredRetention)

        center.getDeliveredNotifications { delivered in
            let newest = delivered.max { $0.date < $1.date }
            let staleIDs = delivered
                .filter { $0.request.identifier != newest?.request.identifier || $0.date < cutoff }
                .map(\.request.identifier)
            guard !staleIDs.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: staleIDs)
            print("[Befoor] Tidied \(staleIDs.count) delivered notification(s)")
        }
    }

    /// Removes every delivered notification except `keepIdentifier`.
    private func clearDelivered(except keepIdentifier: String) {
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
    /// Routes by category: alarm → banner + sound; reminder → banner + sound + list.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let category = notification.request.content.categoryIdentifier

        // The newest alert supersedes everything already in Notification Center,
        // whether it's for the same meeting or a new one.
        clearDelivered(except: notification.request.identifier)

        if category == ReminderAction.category {
            // Person reminders: show banner, play sound, show in list
            completionHandler([.banner, .sound, .list])
            return
        }

        // Alarm notifications (fallback when AlarmKit isn't used). The sound is
        // already silenced in the content when Sound is off.
        completionHandler([.banner, .sound])
    }

    /// Handle Snooze / Dismiss tap — routes by category.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
            tidyDeliveredNotifications()
        }

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
        // Later alerts for the meeting stay scheduled, matching the alarm's Snooze.
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
        content.sound              = AppSettings.shared.soundEnabled ? sound.notificationSound : nil
        content.categoryIdentifier = personName != nil ? AlarmAction.personCategory : AlarmAction.category
        content.interruptionLevel  = .timeSensitive
        if let personName {
            content.userInfo["personName"] = personName
        }

        // Delivered banners are not touched here — scheduling runs ahead of time
        // (and on every sync), so clearing them now would wipe an alert the user
        // hasn't seen yet. Clearing happens when the next alert is presented, and
        // in tidyDeliveredNotifications().

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
}
