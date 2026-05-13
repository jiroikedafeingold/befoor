import Foundation
import SwiftData

@Model
final class Reminder {
    var id: UUID = UUID()
    var title: String = ""
    var fireDate: Date = Date()
    var notificationIdentifier: String?
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var lastModified: Date = Date()
    /// Number of days to snooze (used for snooze actions: 1, 3, or 7 days)
    var snoozeDays: Int?
    var personID: UUID?
    var person: Person?

    init(
        title: String,
        fireDate: Date,
        notificationIdentifier: String? = nil,
        isCompleted: Bool = false,
        person: Person? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.fireDate = fireDate
        self.notificationIdentifier = notificationIdentifier
        self.isCompleted = isCompleted
        self.createdAt = Date()
        self.personID = person?.id
        self.person = person
    }
}
