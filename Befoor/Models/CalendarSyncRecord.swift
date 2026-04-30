import Foundation
import SwiftData

/// Tracks which calendar events have already been synced to avoid duplicates.
@Model
final class CalendarSyncRecord {
    var eventIdentifier: String = ""
    var eventTitle: String = ""
    var eventDate: Date = Date()
    var personName: String?
    var syncedAt: Date = Date()

    init(
        eventIdentifier: String,
        eventTitle: String,
        eventDate: Date,
        personName: String? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.eventTitle = eventTitle
        self.eventDate = eventDate
        self.personName = personName
        self.syncedAt = Date()
    }
}
