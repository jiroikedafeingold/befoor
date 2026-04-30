import SwiftUI

struct FollowUpRowView: View {
    let followUp: FollowUp
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: followUp.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(followUp.isCompleted ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(followUp.text)
                    .font(.body)
                    .strikethrough(followUp.isCompleted)
                    .foregroundStyle(followUp.isCompleted ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let dueDate = followUp.dueDate {
                        let isOverdue = !followUp.isCompleted && dueDate < Date()
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text(dueDate, format: .dateTime.month().day())
                        }
                        .font(.caption)
                        .foregroundStyle(isOverdue ? .red : .secondary)
                    }
                    if followUp.isRecurring {
                        Label("Recurring", systemImage: "repeat")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
