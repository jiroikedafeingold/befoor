import SwiftUI

struct ReminderRowView: View {
    let reminder: Reminder

    private var isOverdue: Bool {
        !reminder.isCompleted && reminder.fireDate < Date()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.isCompleted ? "bell.slash" : "bell.fill")
                .foregroundStyle(isOverdue ? .red : .indigo)
                .font(.body)

            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(.body)
                    .lineLimit(2)

                Text(reminder.fireDate, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(isOverdue ? .red : .secondary)

                if let snoozeDays = reminder.snoozeDays {
                    Text("Snoozed \(snoozeDays) day\(snoozeDays == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
