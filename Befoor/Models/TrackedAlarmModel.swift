import Foundation

/// Lightweight alarm record — kept in memory and snapshotted to a shared JSON file
/// for the widget.
struct TrackedAlarmModel: Codable, Identifiable {
    var eventIdentifier: String
    var notificationIdentifier: String
    var eventStartDate: Date
    var eventTitle: String
    var calendarIdentifier: String
    /// The meeting's video-call link (Zoom, Meet, Teams…), if it has one.
    var joinURL: URL?
    /// "removed" or "changed" when the meeting's link changed since Befoor first saw it.
    var linkChange: String?
    /// Skipped from the list, the widget or Siri; shown, but gets no alarms.
    var isSkipped: Bool = false

    var id: String { eventIdentifier }

    init(
        eventIdentifier: String,
        notificationIdentifier: String,
        eventStartDate: Date,
        eventTitle: String,
        calendarIdentifier: String,
        joinURL: URL? = nil,
        linkChange: String? = nil,
        isSkipped: Bool = false
    ) {
        self.eventIdentifier = eventIdentifier
        self.notificationIdentifier = notificationIdentifier
        self.eventStartDate = eventStartDate
        self.eventTitle = eventTitle
        self.calendarIdentifier = calendarIdentifier
        self.joinURL = joinURL
        self.linkChange = linkChange
        self.isSkipped = isSkipped
    }
}
