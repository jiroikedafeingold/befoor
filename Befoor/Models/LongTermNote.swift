import Foundation
import SwiftData

@Model
final class LongTermNote {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var person: Person?

    init(text: String, person: Person? = nil) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.person = person
    }
}
