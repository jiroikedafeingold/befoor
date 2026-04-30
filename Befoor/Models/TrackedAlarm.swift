import Foundation
import Combine
import SwiftData

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

/// Persists the mapping of eventIdentifier → TrackedAlarmModel using SwiftData.
@MainActor
final class TrackedAlarmsStore: ObservableObject {
    static let shared = TrackedAlarmsStore()

    @Published private(set) var alarms: [String: TrackedAlarmModel] = [:]   // keyed by eventIdentifier

    private var modelContext: ModelContext?
    private let legacyKey = "bf_trackedAlarms"

    private init() {}

    // MARK: Configuration

    /// Call once from ContentView's .task to inject the SwiftData context.
    func configure(with context: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = context
        migrateFromUserDefaults()
        load()
    }

    // MARK: Public API

    func alarm(for eventIdentifier: String) -> TrackedAlarmModel? {
        alarms[eventIdentifier]
    }

    func upsert(_ alarm: TrackedAlarmModel) {
        if let existing = alarms[alarm.eventIdentifier] {
            existing.notificationIdentifier = alarm.notificationIdentifier
            existing.eventStartDate = alarm.eventStartDate
            existing.eventTitle = alarm.eventTitle
            existing.calendarIdentifier = alarm.calendarIdentifier
        } else {
            modelContext?.insert(alarm)
            alarms[alarm.eventIdentifier] = alarm
        }
        save()
    }

    func remove(eventIdentifier: String) {
        if let existing = alarms.removeValue(forKey: eventIdentifier) {
            modelContext?.delete(existing)
            save()
        }
    }

    func removeAll() {
        for alarm in alarms.values {
            modelContext?.delete(alarm)
        }
        alarms.removeAll()
        save()
    }

    /// Remove alarms whose event start dates are in the past (cleanup)
    func prunePast() {
        let now = Date()
        let stale = alarms.filter { $0.value.eventStartDate < now }
        for (key, model) in stale {
            alarms.removeValue(forKey: key)
            modelContext?.delete(model)
        }
        if !stale.isEmpty { save() }
    }

    // MARK: Persistence

    private func save() {
        try? modelContext?.save()
    }

    private func load() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<TrackedAlarmModel>()
        if let results = try? context.fetch(descriptor) {
            alarms = Dictionary(results.map { ($0.eventIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
        }
    }

    // MARK: Migration

    /// One-time migration from UserDefaults → SwiftData.
    private func migrateFromUserDefaults() {
        guard let context = modelContext,
              let data = UserDefaults.standard.data(forKey: legacyKey),
              let legacy = try? JSONDecoder().decode([String: TrackedAlarm].self, from: data)
        else { return }

        for (_, alarm) in legacy {
            let model = TrackedAlarmModel(
                eventIdentifier: alarm.eventIdentifier,
                notificationIdentifier: alarm.notificationIdentifier,
                eventStartDate: alarm.eventStartDate,
                eventTitle: alarm.eventTitle,
                calendarIdentifier: alarm.calendarIdentifier
            )
            context.insert(model)
        }
        try? context.save()
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}
