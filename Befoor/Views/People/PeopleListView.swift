import SwiftUI
import SwiftData

struct PeopleListView: View {
    let syncCoordinator: SyncCoordinator
    @Binding var navigationPath: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.lastMeetingDate, order: .forward) private var people: [Person]
    @Query(filter: #Predicate<Note> { $0.isGlobal == true },
           sort: \Note.meetingDate, order: .reverse)
    private var globalNotes: [Note]
    @State private var searchText = ""
    @State private var showAddPerson = false
    @State private var showAddGlobalNote = false

    /// People sorted by soonest upcoming meeting first, then by name for those without a date.
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
            if people.isEmpty {
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
                        Task { await syncCoordinator.performFullSync() }
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
            await syncCoordinator.performFullSync()
        }
        .alert("Add Person", isPresented: $showAddPerson) {
            AddPersonAlert(modelContext: modelContext)
        }
        .sheet(isPresented: $showAddGlobalNote) {
            AddGlobalNoteView()
        }
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
                Task { await syncCoordinator.performFullSync() }
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
                        Button {
                            navigationPath.append(person.persistentModelID)
                        } label: {
                            PersonRowView(person: person)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button {
                                person.isPinned.toggle()
                                try? modelContext.save()
                            } label: {
                                Label("Unpin", systemImage: "pin.slash")
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
            }

            Section(pinnedPeople.isEmpty ? "People" : "Others") {
                ForEach(unpinnedPeople) { person in
                    Button {
                        navigationPath.append(person.persistentModelID)
                    } label: {
                        PersonRowView(person: person)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button {
                            person.isPinned.toggle()
                            try? modelContext.save()
                        } label: {
                            Label("Pin", systemImage: "pin")
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
