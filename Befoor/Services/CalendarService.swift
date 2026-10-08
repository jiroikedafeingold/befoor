import EventKit
import Foundation

// MARK: - CalendarService

final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let store = EKEventStore()

    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var availableCalendars: [EKCalendar] = []

    private init() {
        updateStatus()
        observeStoreChanges()
    }

    // MARK: Authorization

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            await MainActor.run { self.updateStatus() }
            return granted
        } catch {
            return false
        }
    }

    private func updateStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if isAuthorized {
            refreshCalendars()
        }
    }

    // MARK: Calendars

    func refreshCalendars() {
        availableCalendars = store.calendars(for: .event)
            .sorted { $0.title < $1.title }
    }

    func calendar(for identifier: String) -> EKCalendar? {
        store.calendar(withIdentifier: identifier)
    }

    // MARK: Events

    /// Identifiers of every event calendar on the device right now.
    var allCalendarIdentifiers: Set<String> {
        guard isAuthorized else { return [] }
        return Set(store.calendars(for: .event).map(\.calendarIdentifier))
    }

    /// Fetch all events between now and `lookAheadDays` days from now, from every
    /// calendar except the ones the user turned off.
    func fetchUpcomingEvents(lookAheadDays: Int, excludedIdentifiers: Set<String>) -> [EKEvent] {
        guard isAuthorized else { return [] }

        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: lookAheadDays, to: now) else {
            return []
        }

        let calendars = store.calendars(for: .event)
            .filter { !excludedIdentifiers.contains($0.calendarIdentifier) }

        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
    }

    /// Finds the specific occurrence of an event. `event(withIdentifier:)` returns the
    /// first occurrence of a recurring series, so match on the start date instead.
    func event(identifier: String, startingAt start: Date) -> EKEvent? {
        guard isAuthorized else { return nil }
        let predicate = store.predicateForEvents(
            withStart: start.addingTimeInterval(-60),
            end: start.addingTimeInterval(60),
            calendars: nil
        )
        return store.events(matching: predicate).first {
            $0.eventIdentifier == identifier && abs($0.startDate.timeIntervalSince(start)) < 60
        }
    }

    // MARK: Change Observation

    var onStoreChanged: (() -> Void)?

    private func observeStoreChanges() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.onStoreChanged?()
        }
    }
}
