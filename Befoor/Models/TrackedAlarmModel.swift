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
    /// The person's short note for this meeting.
    var note: String?
    /// True for the day's first meeting time, which can ring earlier
    /// (AppSettings.firstMeetingAlertMinutes). Optional so older snapshots decode.
    var firstOfDay: Bool?

    /// One per occurrence: a repeating meeting shares its eventIdentifier
    /// across every occurrence, so the start time is part of the identity.
    var id: String { "\(eventIdentifier)|\(Int(eventStartDate.timeIntervalSince1970))" }

    init(
        eventIdentifier: String,
        notificationIdentifier: String,
        eventStartDate: Date,
        eventTitle: String,
        calendarIdentifier: String,
        joinURL: URL? = nil,
        linkChange: String? = nil,
        isSkipped: Bool = false,
        note: String? = nil,
        firstOfDay: Bool? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.notificationIdentifier = notificationIdentifier
        self.eventStartDate = eventStartDate
        self.eventTitle = eventTitle
        self.calendarIdentifier = calendarIdentifier
        self.joinURL = joinURL
        self.linkChange = linkChange
        self.isSkipped = isSkipped
        self.note = note
        self.firstOfDay = firstOfDay
    }
}
