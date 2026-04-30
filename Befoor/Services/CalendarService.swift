import EventKit
import Contacts
import Foundation

// MARK: - DetectedMeeting

/// A 1:1 meeting detected from the user's calendar.
struct DetectedMeeting: Sendable {
    let eventIdentifier: String
    let eventTitle: String
    let startDate: Date
    let otherPersonName: String
    let otherPersonEmail: String?
}

// MARK: - CalendarService

final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let store = EKEventStore()
    private let contactStore = CNContactStore()

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

    var isContactsAuthorized: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
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

    func requestContactsAccess() async -> Bool {
        do {
            return try await contactStore.requestAccess(for: .contacts)
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

    /// Fetch all events between now and `lookAheadDays` days from now,
    /// filtered to the user's selected calendars.
    func fetchUpcomingEvents(lookAheadDays: Int, selectedIdentifiers: Set<String>) -> [EKEvent] {
        guard isAuthorized else { return [] }

        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: lookAheadDays, to: now) else {
            return []
        }

        let calendars: [EKCalendar]
        if selectedIdentifiers.isEmpty {
            calendars = store.calendars(for: .event)
        } else {
            calendars = selectedIdentifiers.compactMap { store.calendar(withIdentifier: $0) }
        }

        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: 1:1 Meeting Detection

    /// Scan calendar events for likely 1:1 meetings based on detection keywords.
    func scanForOneOnOnes(from startDate: Date, to endDate: Date, keywords: [String]) -> [DetectedMeeting] {
        guard isAuthorized else { return [] }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = store.events(matching: predicate)

        var results: [DetectedMeeting] = []

        for event in events {
            guard !event.isAllDay else { continue }
            let title = event.title ?? ""

            // Check if the event title matches any detection keywords
            guard matchesKeywords(title: title, keywords: keywords) else { continue }

            // Try to extract the other person from attendees first,
            // then fall back to parsing the name from the event title.
            let name: String
            let email: String?
            if let (attendeeName, attendeeEmail) = extractOtherPerson(from: event) {
                name = attendeeName
                email = attendeeEmail
            } else if let parsedName = extractNameFromTitle(title: title, keywords: keywords) {
                name = parsedName
                email = nil
            } else {
                continue
            }

            results.append(DetectedMeeting(
                eventIdentifier: event.eventIdentifier,
                eventTitle: title,
                startDate: event.startDate,
                otherPersonName: name,
                otherPersonEmail: email
            ))
        }

        return results
    }

    // MARK: Private Helpers

    private func matchesKeywords(title: String, keywords: [String]) -> Bool {
        let lower = title.lowercased()
        for keyword in keywords {
            if lower.contains(keyword.lowercased()) { return true }
        }
        return false
    }

    /// Try to extract a person's name from the event title by stripping detection keywords
    /// and common prepositions (e.g. "1:1 with Jane Doe" → "Jane Doe").
    private func extractNameFromTitle(title: String, keywords: [String]) -> String? {
        var cleaned = title

        // Remove detection keywords (case-insensitive)
        for keyword in keywords {
            if let range = cleaned.range(of: keyword, options: .caseInsensitive) {
                cleaned.replaceSubrange(range, with: "")
            }
        }

        // Remove common prepositions/connectors
        let noise = ["with", "w/", " - ", " — ", " – ", " / ", ":", "|"]
        for word in noise {
            cleaned = cleaned.replacingOccurrences(of: word, with: " ", options: .caseInsensitive)
        }

        // Trim and collapse whitespace
        let name = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Only return if we got something that looks like a name (at least 2 characters)
        return name.count >= 2 ? name : nil
    }

    /// Extract the "other" attendee from a meeting (the one who isn't the current user).
    private func extractOtherPerson(from event: EKEvent) -> (name: String, email: String?)? {
        guard let attendees = event.attendees else { return nil }

        // Filter out the organizer / current user and resources
        let others = attendees.filter { attendee in
            !attendee.isCurrentUser &&
            attendee.participantType == .person
        }

        // A 1:1 should have exactly one other person
        guard others.count == 1, let other = others.first else { return nil }

        let email = other.url.absoluteString
            .replacingOccurrences(of: "mailto:", with: "")

        // Resolve a human-readable name: try Contacts first, then the attendee
        // name (if it's not just an email), and finally infer from the email.
        let name: String
        if let contactName = resolveContactName(email: email) {
            name = contactName
        } else if let attendeeName = other.name, !attendeeName.isEmpty, !attendeeName.contains("@") {
            name = attendeeName
        } else {
            name = inferName(from: email)
        }

        return (name, email.isEmpty ? nil : email)
    }

    /// Try to look up a real name from Contacts by email address.
    private func resolveContactName(email: String) -> String? {
        guard isContactsAuthorized, !email.isEmpty else { return nil }

        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]

        guard let contacts = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: keys),
              let contact = contacts.first else { return nil }

        let full = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? nil : full
    }

    /// Infer a display name from an email address (e.g. "jane.doe@company.com" → "Jane Doe").
    private func inferName(from email: String) -> String {
        guard let local = email.components(separatedBy: "@").first else { return email }
        return local
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
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
