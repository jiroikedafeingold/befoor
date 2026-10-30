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

    /// Fetch all events between `start` (default now) and `lookAheadDays` days
    /// from now, from every calendar except the ones the user turned off.
    func fetchUpcomingEvents(from start: Date? = nil, lookAheadDays: Int, excludedIdentifiers: Set<String>) -> [EKEvent] {
        guard isAuthorized else { return [] }

        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: lookAheadDays, to: now) else {
            return []
        }

        let calendars = store.calendars(for: .event)
            .filter { !excludedIdentifiers.contains($0.calendarIdentifier) }

        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: start ?? now, end: end, calendars: calendars)
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

    // MARK: Video calls

    /// Services whose links are meeting joins rather than ordinary web pages.
    private static let videoCallHosts = [
        "zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "facetime.apple.com", "whereby.com", "gotomeeting.com", "chime.aws",
    ]

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// "cancelled" when the organizer cancelled the meeting, "declined" when
    /// everyone else invited (people, not rooms) has declined it, else nil.
    func cancellation(for event: EKEvent) -> String? {
        if event.status == .canceled { return "cancelled" }
        let others = (event.attendees ?? []).filter {
            !$0.isCurrentUser && $0.participantType != .room && $0.participantType != .resource
        }
        if !others.isEmpty, others.allSatisfy({ $0.participantStatus == .declined }) { return "declined" }
        return nil
    }

    /// Who else is in the meeting, for its countdown: "Abby Lee, Sam Ortiz +2".
    /// People only (not rooms), leaving out the person and anyone who declined;
    /// nil when there's no one else.
    func participants(for event: EKEvent) -> String? {
        let names = (event.attendees ?? [])
            .filter {
                !$0.isCurrentUser && $0.participantType != .room && $0.participantType != .resource
                    && $0.participantStatus != .declined
            }
            .compactMap { person -> String? in
                if let name = person.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
                let address = person.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                return address.isEmpty ? nil : address
            }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(2).joined(separator: ", ")
        return names.count > 2 ? "\(shown) +\(names.count - 2)" : shown
    }

    /// The event's video-call link, from its URL field, location or notes.
    func joinURL(for event: EKEvent) -> URL? {
        func isVideoCall(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  let host = url.host()?.lowercased() else { return false }
            return Self.videoCallHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if let url = event.url, isVideoCall(url) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let detector = Self.linkDetector else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
            .first(where: isVideoCall)
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
