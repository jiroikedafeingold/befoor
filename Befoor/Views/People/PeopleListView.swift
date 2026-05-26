import SwiftUI
import SwiftData

struct PeopleListView: View {
    let syncCoordinator: SyncCoordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.lastMeetingDate, order: .forward) private var people: [Person]
    @Query(filter: #Predicate<Note> { $0.isGlobal == true },
           sort: \Note.meetingDate, order: .reverse)
    private var globalNotes: [Note]
    @State private var searchText = ""
    @State private var showAddPerson = false
    @State private var showAddGlobalNote = false

    /// Meetings that started within the last hour are considered "in progress"
    /// and sort to the top. Then upcoming meetings by soonest first, then alphabetically.
    private var sortedPeople: [Person] {
        let now = Date()
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

    private var filteredPeople: [Person] {
        if searchText.isEmpty {
            return sortedPeople
        }
        return sortedPeople.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var pinnedPeople: [Person] {
        filteredPeople.filter(\.isPinned)
    }

    private var unpinnedPeople: [Person] {
        filteredPeople.filter { !$0.isPinned }
    }

    var body: some View {
        Group {
            if syncCoordinator.isSyncing && people.isEmpty {
                syncingState
            } else if people.isEmpty {
                emptyState
            } else {
                peopleList
            }
        }
        .navigationTitle("People")
        .searchable(text: $searchText, prompt: "Search people")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if syncCoordinator.isSyncing {
                    ProgressView()
                        .tint(.indigo)
                } else {
                    Button {
                        Task { await syncCoordinator.performFullSync(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddPerson = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await syncCoordinator.performFullSync(force: true)
        }
        .alert("Add Person", isPresented: $showAddPerson) {
            AddPersonAlert(modelContext: modelContext)
        }
        .sheet(isPresented: $showAddGlobalNote) {
            AddGlobalNoteView()
        }
    }

    private var syncingState: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.indigo)

            Text("Syncing people…")
                .font(.title3.weight(.semibold))

            Text("Looking for 1:1 meetings in your calendar.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2")
                .font(.system(size: 64))
                .foregroundStyle(.indigo.opacity(0.5))

            Text("No people yet")
                .font(.title3.weight(.semibold))

            Text("Befoor will automatically detect people from your 1:1 meetings, or you can add them manually.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Sync Calendar") {
                Task { await syncCoordinator.performFullSync(force: true) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(syncCoordinator.isSyncing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var peopleList: some View {
        List {
            Section {
                if globalNotes.isEmpty {
                    Text("No shared notes yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(globalNotes) { note in
                    NoteRowView(note: note)
                }
                .onDelete { offsets in
                    for offset in offsets {
                        modelContext.delete(globalNotes[offset])
                    }
                    try? modelContext.save()
                }

                Button {
                    showAddGlobalNote = true
                } label: {
                    Label("Add Note for Everyone", systemImage: "plus.circle")
                }
            } header: {
                Text("Notes for Everyone")
            }

            if !pinnedPeople.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedPeople) { person in
                        personRow(person, pinAction: "Unpin", pinImage: "pin.slash")
                    }
                }
            }

            Section(pinnedPeople.isEmpty ? "People" : "Others") {
                ForEach(unpinnedPeople) { person in
                    personRow(person, pinAction: "Pin", pinImage: "pin")
                }
            }
        }
    }

    private func personRow(_ person: Person, pinAction: String, pinImage: String) -> some View {
        NavigationLink(value: person.persistentModelID) {
            PersonRowView(person: person)
        }
        .swipeActions(edge: .leading) {
            Button {
                person.isPinned.toggle()
                try? modelContext.save()
            } label: {
                Label(pinAction, systemImage: pinImage)
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                modelContext.delete(person)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Person Alert

private struct AddPersonAlert: View {
    let modelContext: ModelContext
    @State private var name = ""

    var body: some View {
        TextField("Name", text: $name)
        Button("Add") {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let person = Person(name: trimmed)
            modelContext.insert(person)
            try? modelContext.save()
        }
        Button("Cancel", role: .cancel) {}
    }
}
