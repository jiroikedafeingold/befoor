import SwiftUI

struct AddReminderView: View {
    let person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var fireDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("What should you be reminded about?", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("When") {
                    DatePicker("Date & Time", selection: $fireDate)
                }
            }
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }

                        let notifID = "reminder_\(UUID().uuidString)"
                        let reminder = Reminder(
                            title: trimmed,
                            fireDate: fireDate,
                            notificationIdentifier: notifID,
                            person: person
                        )
                        modelContext.insert(reminder)
                        try? modelContext.save()

                        // Schedule the notification
                        let personIDString = person.persistentModelID.hashValue.description
                        Task {
                            await NotificationService.shared.schedulePersonReminder(
                                identifier: notifID,
                                personName: person.name,
                                title: trimmed,
                                fireDate: fireDate,
                                personIDString: personIDString
                            )
                        }

                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
