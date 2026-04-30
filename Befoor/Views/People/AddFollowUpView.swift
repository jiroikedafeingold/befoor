import SwiftUI

struct AddFollowUpView: View {
    let person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var isRecurring = false
    @State private var recurrenceInterval = 7

    var body: some View {
        NavigationStack {
            Form {
                Section("Follow-up") {
                    TextField("What do you need to follow up on?", text: $text, axis: .vertical)
                        .lineLimit(1...5)
                }

                Section("Due Date") {
                    Toggle("Set Due Date", isOn: $hasDueDate)
                        .tint(.indigo)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Recurrence") {
                    Toggle("Recurring", isOn: $isRecurring)
                        .tint(.indigo)
                    if isRecurring {
                        Stepper("Every \(recurrenceInterval) days", value: $recurrenceInterval, in: 1...365)
                    }
                }
            }
            .navigationTitle("Add Follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let followUp = FollowUp(
                            text: trimmed,
                            dueDate: hasDueDate ? dueDate : nil,
                            isRecurring: isRecurring,
                            recurrenceIntervalDays: isRecurring ? recurrenceInterval : nil,
                            person: person
                        )
                        modelContext.insert(followUp)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
