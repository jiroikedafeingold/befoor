import Foundation

/// Stable per-device identifier stored in UserDefaults so it persists across launches.
enum DeviceID {
    static let current: String = {
        let key = "befoor_device_id"
        if let id = UserDefaults.standard.string(forKey: key) {
            return id
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
}

// MARK: - SyncRecordStore

/// File-based store that tracks which calendar events have been synced.
/// Replaces the SwiftData CalendarSyncRecord model so local bookkeeping
/// does not share the persistent store coordinator with CloudKit.
@MainActor
final class SyncRecordStore {
    static let shared = SyncRecordStore()

    struct Record: Codable {
        let eventTitle: String
        let eventDate: Date
        let personName: String?
    }

    private var records: [String: Record] = [:]
    private static let fileName = "sync_records.json"

    private init() {
        load()
    }

    func isAlreadySynced(eventIdentifier: String) -> Bool {
        records[eventIdentifier] != nil
    }

    func personName(forEventIdentifier id: String) -> String? {
        records[id]?.personName
    }

    func record(eventIdentifier: String, eventTitle: String, eventDate: Date, personName: String?) {
        records[eventIdentifier] = Record(
            eventTitle: eventTitle,
            eventDate: eventDate,
            personName: personName
        )
    }

    func clearAll() {
        records.removeAll()
    }

    func clearPast() {
        let now = Date()
        records = records.filter { $0.value.eventDate >= now }
    }

    func save() {
        guard let url = Self.fileURL else { return }
        try? JSONEncoder().encode(records).write(to: url, options: .atomic)
    }

    // MARK: Private

    private func load() {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else { return }
        records = decoded
    }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.befoor.app")?
            .appendingPathComponent(fileName)
    }
}
