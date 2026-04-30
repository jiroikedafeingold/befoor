import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID = UUID()
    var text: String = ""
    var meetingDate: Date = Date()
    var createdAt: Date = Date()
    var isGlobal: Bool = false
    var person: Person?

    init(text: String, meetingDate: Date, person: Person? = nil, isGlobal: Bool = false) {
        self.id = UUID()
        self.text = text
        self.meetingDate = meetingDate
        self.createdAt = Date()
        self.isGlobal = isGlobal
        self.person = person
    }
}
