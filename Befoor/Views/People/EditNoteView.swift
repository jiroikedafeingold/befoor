import SwiftUI

struct EditNoteView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var meetingDate: Date

    init(note: Note) {
        self.note = note
        _text = State(initialValue: note.text)
        _meetingDate = State(initialValue: note.meetingDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meeting Date") {
                    DatePicker("Date", selection: $meetingDate, displayedComponents: .date)
                }

                Section("Note") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        note.text = trimmed
                        note.meetingDate = meetingDate
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
