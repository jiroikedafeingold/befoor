import SwiftUI
import SwiftData

struct WatchPeopleListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Person.lastMeetingDate, order: .forward) private var people: [Person]
    // Tracked so the sort re-evaluates as wall-clock time advances. SwiftUI can't
    // observe Date() inside a computed property, so without this the order would
    // stay frozen at the time of first render even as CloudKit pushes updates.
    @State private var now = Date()

    /// Meetings that started within the last hour are considered "in progress"
    /// and sort to the top. Then upcoming meetings by soonest first, then alphabetically.
    private var sortedPeople: [Person] {
        let oneHourAgo = now.addingTimeInterval(-3600)

        func sortDate(_ d: Date?) -> Date? {
            guard let d else { return nil }
            if d > now { return d }        // upcoming
            if d > oneHourAgo { return d } // in progress
            return nil                     // past
        }

        return people.sorted { a, b in
            let dateA = sortDate(a.lastMeetingDate)
            let dateB = sortDate(b.lastMeetingDate)
            switch (dateA, dateB) {
            case let (dA?, dB?):
                return dA < dB
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    private var pinnedPeople: [Person] {
        sortedPeople.filter(\.isPinned)
    }

    private var unpinnedPeople: [Person] {
        sortedPeople.filter { !$0.isPinned }
    }

    var body: some View {
        List {
            if people.isEmpty {
                ContentUnavailableView("No People", systemImage: "person.2",
                                       description: Text("People will appear here after syncing on your iPhone."))
            } else {
                if !pinnedPeople.isEmpty {
                    Section("Pinned") {
                        ForEach(pinnedPeople) { person in
                            NavigationLink {
                                WatchPersonDetailView(person: person)
                            } label: {
                                WatchPersonRow(person: person)
                            }
                        }
                    }
                }

                Section(pinnedPeople.isEmpty ? "People" : "Others") {
                    ForEach(unpinnedPeople) { person in
                        NavigationLink {
                            WatchPersonDetailView(person: person)
                        } label: {
                            WatchPersonRow(person: person)
                        }
                    }
                }
            }
        }
        .navigationTitle("People")
        .task {
            now = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { now = Date() }
        }
    }
}

private struct WatchPersonRow: View {
    let person: Person

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(person.name)
                    .font(.headline)
                    .lineLimit(1)
                if person.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if let date = person.lastMeetingDate {
                if date > Date() {
                    Text("in \(date, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(date, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
