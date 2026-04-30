import SwiftUI
import SwiftData

struct WatchPersonDetailView: View {
    let person: Person
    @Query(filter: #Predicate<Note> { $0.isGlobal == true },
           sort: \Note.meetingDate, order: .reverse)
    private var globalNotes: [Note]

    var body: some View {
        List {
            followUpsSection
            notesSection
            longTermNotesSection
            globalNotesSection
        }
        .navigationTitle(person.name)
    }

    // MARK: - Sections

    @ViewBuilder
    private var followUpsSection: some View {
        let active = (person.followUps ?? [])
            .filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        if !active.isEmpty {
            Section("Follow-ups") {
                ForEach(active) { followUp in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(followUp.text)
                            .font(.body)
                            .lineLimit(3)
                        if let due = followUp.dueDate {
                            Text("Due \(due, format: .dateTime.month().day())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        let notes = (person.notes ?? []).sorted { $0.meetingDate > $1.meetingDate }

        Section("Notes") {
            if notes.isEmpty {
                Text("No notes yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.meetingDate, format: .dateTime.month().day())
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                    Text(note.text)
                        .font(.body)
                        .lineLimit(4)
                }
            }
        }
    }

    @ViewBuilder
    private var longTermNotesSection: some View {
        let longTermNotes = (person.longTermNotes ?? []).sorted { $0.createdAt > $1.createdAt }

        if !longTermNotes.isEmpty {
            Section("Long-term Notes") {
                ForEach(longTermNotes) { note in
                    Text(note.text)
                        .font(.body)
                        .lineLimit(4)
                }
            }
        }
    }

    @ViewBuilder
    private var globalNotesSection: some View {
        if !globalNotes.isEmpty {
            Section("Notes for Everyone") {
                ForEach(globalNotes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.meetingDate, format: .dateTime.month().day())
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                        Text(note.text)
                            .font(.body)
                            .lineLimit(4)
                    }
                }
            }
        }
    }
}
