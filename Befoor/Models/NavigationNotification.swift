import Foundation

extension Notification.Name {
    /// Posted when a person reminder notification is tapped.
    /// The `userInfo` dictionary contains `"personID"` with the person's `PersistentIdentifier`.
    static let navigateToPerson = Notification.Name("navigateToPerson")
}
