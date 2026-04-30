import SwiftUI
import SwiftData

/// Shows a pre-meeting preparation view with the person's notes and follow-ups.
struct PreMeetingReminderView: View {
    let person: Person
    @Query(filter: #Predicate<Note> { $0.isGlobal == true },
           sort: \Note.meetingDate, order: .reverse)
    private var globalNotes: [Note]

    var body: some View {
        List {
            Section("Open Follow-ups") {
                let active = (person.followUps ?? []).filter { !$0.isCompleted }
                    .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                if active.isEmpty {
                    Text("No open follow-ups")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(active) { followUp in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(followUp.text)
                                .font(.body)
                            if let dueDate = followUp.dueDate {
                                Text("Due: \(dueDate, format: .dateTime.month().day())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Long-term Notes") {
                let notes = (person.longTermNotes ?? []).sorted { $0.createdAt > $1.createdAt }
                if notes.isEmpty {
                    Text("No long-term notes")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(notes) { note in
                        Text(note.text)
                            .font(.body)
                            .lineLimit(3)
                    }
                }
            }

            Section("Recent Notes") {
                let recentNotes = (person.notes ?? []).sorted { $0.meetingDate > $1.meetingDate }.prefix(3)
                if recentNotes.isEmpty {
                    Text("No recent notes")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentNotes) { note in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.meetingDate, format: .dateTime.month().day())
                                .font(.caption)
                                .foregroundStyle(.indigo)
                            Text(note.text)
                                .font(.body)
                                .lineLimit(3)
                        }
                    }
                }
            }

            if !globalNotes.isEmpty {
                Section("Notes for Everyone") {
                    ForEach(globalNotes) { note in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.meetingDate, format: .dateTime.month().day())
                                .font(.caption)
                                .foregroundStyle(.indigo)
                            Text(note.text)
                                .font(.body)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
        .navigationTitle("Prep: \(person.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
