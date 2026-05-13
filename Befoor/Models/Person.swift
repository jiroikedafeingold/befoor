import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    var email: String?
    var calendarEventTitle: String?
    var lastMeetingDate: Date?
    var createdAt: Date = Date()
    var isPinned: Bool = false
    /// The device that last authoritatively set lastMeetingDate.
    /// Other devices defer to this value via CloudKit rather than overwriting it.
    var meetingDateDeviceID: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Note.person)
    var notes: [Note]?

    @Relationship(deleteRule: .cascade, inverse: \FollowUp.person)
    var followUps: [FollowUp]?

    @Relationship(deleteRule: .cascade, inverse: \LongTermNote.person)
    var longTermNotes: [LongTermNote]?

    @Relationship(deleteRule: .cascade, inverse: \Reminder.person)
    var reminders: [Reminder]?

    init(
        name: String,
        email: String? = nil,
        calendarEventTitle: String? = nil,
        lastMeetingDate: Date? = nil,
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.calendarEventTitle = calendarEventTitle
        self.lastMeetingDate = lastMeetingDate
        self.createdAt = Date()
        self.isPinned = isPinned
    }
}
