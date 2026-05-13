import SwiftUI

struct EditLongTermNoteView: View {
    @Bindable var note: LongTermNote
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(note: LongTermNote) {
        self.note = note
        _text = State(initialValue: note.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Edit Long-term Note")
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
                        note.lastModified = Date()
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
