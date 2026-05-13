import SwiftUI
import SwiftData

struct WatchPeopleListView: View {
    @Query(sort: \Person.lastMeetingDate, order: .forward) private var people: [Person]

    private var sortedPeople: [Person] {
        people.sorted { a, b in
            switch (a.lastMeetingDate, b.lastMeetingDate) {
            case let (dateA?, dateB?):
                return dateA < dateB
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
