import Foundation
import SwiftData

/// Single CloudKit-synced record that holds the entire alarm list as JSON.
/// Only the main device writes to it; secondary devices read via CloudKit import.
@Model
final class AlarmListSnapshot {
    var alarmsJSON: Data = Data()
    var lastUpdated: Date = Date()

    init() {}
}

/// Lightweight alarm record — kept in memory and snapshotted to a shared JSON file
/// for the widget. No longer a SwiftData model so it cannot interfere with CloudKit exports.
struct TrackedAlarmModel: Codable, Identifiable {
    var eventIdentifier: String
    var notificationIdentifier: String
    var eventStartDate: Date
    var eventTitle: String
    var calendarIdentifier: String
    var deviceIdentifier: String

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
        self.deviceIdentifier = DeviceID.current
    }
}
