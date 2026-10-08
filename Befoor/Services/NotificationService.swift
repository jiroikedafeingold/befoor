import UserNotifications
import Foundation

// MARK: - Action / Category identifiers

enum AlarmAction {
    static let snooze     = "BEFOOR_SNOOZE"
    static let dismiss    = "BEFOOR_DISMISS"
    static let category   = "BEFOOR_ALARM"
}

// MARK: - NotificationService

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

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

        center.setNotificationCategories([alarmCategory])
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
        sound: BefoorSound
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
                sound:          sound
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
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // The newest alert supersedes everything already in Notification Center,
        // whether it's for the same meeting or a new one.
        clearDelivered(except: notification.request.identifier)

        // Alarm notifications (fallback when AlarmKit isn't used). The sound is
        // already silenced in the content when Sound is off.
        completionHandler([.banner, .sound])
    }

    /// Handle Snooze / Dismiss tap.
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

        guard category == AlarmAction.category else { return }

        switch response.actionIdentifier {
        case AlarmAction.snooze:
            let base = stripAlarmSuffix(notif.request.identifier)
            snoozeAlarm(base: base, content: notif.request.content)

        case UNNotificationDefaultActionIdentifier:
            // Tapping the notification banner snoozes.
            let base = stripAlarmSuffix(notif.request.identifier)
            snoozeAlarm(base: base, content: notif.request.content)

        case AlarmAction.dismiss, UNNotificationDismissActionIdentifier:
            let base = stripAlarmSuffix(notif.request.identifier)
            cancel(identifiers: [base])

        default:
            break
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

    // MARK: Schedule helpers

    private func schedule(
        id: String,
        title: String,
        subtitle: String,
        calendarName: String,
        threadID: String,
        date: Date,
        sound: BefoorSound
    ) async {
        let content = UNMutableNotificationContent()
        content.title              = title
        content.subtitle           = subtitle
        content.body               = calendarName
        content.threadIdentifier   = threadID
        content.summaryArgument    = title
        content.sound              = AppSettings.shared.soundEnabled ? sound.notificationSound : nil
        content.categoryIdentifier = AlarmAction.category
        content.interruptionLevel  = .timeSensitive

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
