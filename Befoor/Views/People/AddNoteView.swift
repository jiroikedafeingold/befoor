import SwiftUI

struct AddNoteView: View {
    let person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var meetingDate = Date()

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
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let note = Note(text: trimmed, meetingDate: meetingDate, person: person)
                        modelContext.insert(note)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
