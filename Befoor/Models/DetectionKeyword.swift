import Foundation
import SwiftData

/// Keywords used to detect 1:1 meetings from calendar event titles.
@Model
final class DetectionKeyword {
    var id: UUID = UUID()
    var keyword: String = ""
    var isEnabled: Bool = true
    var createdAt: Date = Date()

    init(keyword: String, isEnabled: Bool = true) {
        self.id = UUID()
        self.keyword = keyword
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }
}
