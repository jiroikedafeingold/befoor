import SwiftUI

struct EditFollowUpView: View {
    @Bindable var followUp: FollowUp
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var isRecurring: Bool
    @State private var recurrenceInterval: Int

    init(followUp: FollowUp) {
        self.followUp = followUp
        _text = State(initialValue: followUp.text)
        _hasDueDate = State(initialValue: followUp.dueDate != nil)
        _dueDate = State(initialValue: followUp.dueDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _isRecurring = State(initialValue: followUp.isRecurring)
        _recurrenceInterval = State(initialValue: followUp.recurrenceIntervalDays ?? 7)
    }

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
            .navigationTitle("Edit Follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        followUp.text = trimmed
                        followUp.dueDate = hasDueDate ? dueDate : nil
                        followUp.isRecurring = isRecurring
                        followUp.recurrenceIntervalDays = isRecurring ? recurrenceInterval : nil
                        followUp.lastModified = Date()
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
