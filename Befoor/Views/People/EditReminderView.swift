import SwiftUI

struct EditReminderView: View {
    @Bindable var reminder: Reminder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var fireDate: Date

    init(reminder: Reminder) {
        self.reminder = reminder
        _title = State(initialValue: reminder.title)
        _fireDate = State(initialValue: reminder.fireDate)
    }

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
            .navigationTitle("Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        reminder.title = trimmed

                        if fireDate != reminder.fireDate {
                            if let oldID = reminder.notificationIdentifier {
                                NotificationService.shared.cancelNotification(identifier: oldID)
                            }
                            let newID = "reminder_\(UUID().uuidString)"
                            reminder.notificationIdentifier = newID
                            reminder.fireDate = fireDate

                            if let person = reminder.person {
                                let personIDString = person.persistentModelID.hashValue.description
                                Task {
                                    await NotificationService.shared.schedulePersonReminder(
                                        identifier: newID,
                                        personName: person.name,
                                        title: trimmed,
                                        fireDate: fireDate,
                                        personIDString: personIDString
                                    )
                                }
                            }
                        } else {
                            reminder.fireDate = fireDate
                        }

                        reminder.lastModified = Date()
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
