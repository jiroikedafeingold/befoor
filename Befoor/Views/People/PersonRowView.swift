import SwiftUI

struct PersonRowView: View {
    let person: Person

    private var meetingText: String? {
        guard let date = person.lastMeetingDate, date > Date() else { return nil }
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "EEE h:mm a"
            return formatter.string(from: date)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(person.name)
                .font(.body.weight(.medium))
                .lineLimit(1)

            if person.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let meeting = meetingText {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(meeting)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let noteCount = (person.notes ?? []).count
            let followUpCount = (person.followUps ?? []).filter { !$0.isCompleted }.count
            if noteCount > 0 || followUpCount > 0 {
                Text("·")
                    .foregroundStyle(.secondary)
            }
            if noteCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "note.text")
                    Text("\(noteCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if followUpCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "checklist")
                    Text("\(followUpCount)")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Spacer()
        }
        .frame(minHeight: 44)
    }
}
