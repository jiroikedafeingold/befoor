import Foundation
import SwiftData

/// SwiftData model for persisting tracked alarms.
/// Replaces the old UserDefaults-backed TrackedAlarm struct.
@Model
final class TrackedAlarmModel {
    /// The EventKit event's unique identifier
    var eventIdentifier: String = ""
    /// The UNUserNotification request identifier we created
    var notificationIdentifier: String = ""
    /// The event start date — used to detect changes
    var eventStartDate: Date = Date()
    /// Human-readable title stored so we can show it without re-fetching the event
    var eventTitle: String = ""
    /// Calendar identifier for display
    var calendarIdentifier: String = ""

    init(
        eventIdentifier: String,
        notificationIdentifier: String,
        eventStartDate: Date,
        eventTitle: String,
        calendarIdentifier: String
    ) {
        self.eventIdentifier = eventIdentifier
        self.notificationIdentifier = notificationIdentifier
        self.eventStartDate = eventStartDate
        self.eventTitle = eventTitle
        self.calendarIdentifier = calendarIdentifier
    }
}
