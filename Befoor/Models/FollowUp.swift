import Foundation
import SwiftData

@Model
final class FollowUp {
    var id: UUID = UUID()
    var text: String = ""
    var isCompleted: Bool = false
    var dueDate: Date?
    var createdAt: Date = Date()
    var isRecurring: Bool = false
    /// Recurrence interval in days (e.g. 7 for weekly, 14 for biweekly)
    var recurrenceIntervalDays: Int?
    var person: Person?

    init(
        text: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        isRecurring: Bool = false,
        recurrenceIntervalDays: Int? = nil,
        person: Person? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.createdAt = Date()
        self.isRecurring = isRecurring
        self.recurrenceIntervalDays = recurrenceIntervalDays
        self.person = person
    }
}
