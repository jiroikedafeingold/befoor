import Foundation
import Combine

// MARK: - TrackedAlarm (legacy, used only for migration)

/// Legacy struct kept for one-time UserDefaults → SwiftData migration.
struct TrackedAlarm: Codable, Identifiable {
    var eventIdentifier: String
    var notificationIdentifier: String
    var eventStartDate: Date
    var eventTitle: String
    var calendarIdentifier: String

    var id: String { notificationIdentifier }
}

// MARK: - TrackedAlarmsStore

/// In-memory store for tracked alarms. Writes a JSON snapshot to the app group
/// container so the widget can read it.
@MainActor
final class TrackedAlarmsStore: ObservableObject {
    static let shared = TrackedAlarmsStore()

    @Published private(set) var alarms: [String: TrackedAlarmModel] = [:]

    private static let snapshotFileName = "tracked_alarms.json"
    private let legacyKey = "bf_trackedAlarms"

    private init() {
        loadSnapshot()
        cleanupLegacyDefaults()
    }

    // MARK: Public API

    func alarm(for eventIdentifier: String) -> TrackedAlarmModel? {
        alarms[eventIdentifier]
    }

    func upsert(_ alarm: TrackedAlarmModel) {
        alarms[alarm.eventIdentifier] = alarm
    }

    func remove(eventIdentifier: String) {
        alarms.removeValue(forKey: eventIdentifier)
    }

    func removeAll() {
        alarms.removeAll()
    }

    func prunePast() {
        let now = Date()
        let stale = alarms.filter { $0.value.eventStartDate < now }
        for key in stale.keys {
            alarms.removeValue(forKey: key)
        }
    }

    /// Write the current alarms to a shared JSON file for the widget.
    func saveSnapshot() {
        guard let url = Self.snapshotURL else { return }
        let values = Array(alarms.values)
        try? JSONEncoder().encode(values).write(to: url, options: .atomic)
    }

    // MARK: Private

    private func loadSnapshot() {
        guard let url = Self.snapshotURL,
              let data = try? Data(contentsOf: url),
              let models = try? JSONDecoder().decode([TrackedAlarmModel].self, from: data) else { return }
        alarms = Dictionary(models.map { ($0.eventIdentifier, $0) },
                            uniquingKeysWith: { _, latest in latest })
    }

    private func cleanupLegacyDefaults() {
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.befoor.app")?
            .appendingPathComponent(snapshotFileName)
    }
}
