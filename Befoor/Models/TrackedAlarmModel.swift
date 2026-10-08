import Foundation

/// Lightweight alarm record — kept in memory and snapshotted to a shared JSON file
/// for the widget.
struct TrackedAlarmModel: Codable, Identifiable {
    var eventIdentifier: String
    var notificationIdentifier: String
    var eventStartDate: Date
    var eventTitle: String
    var calendarIdentifier: String

    var id: String { eventIdentifier }

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
