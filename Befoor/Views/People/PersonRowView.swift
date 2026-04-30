import SwiftUI

struct PersonRowView: View {
    let person: Person

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if person.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                if let meetingDate = person.lastMeetingDate {
                    if meetingDate > Date() {
                        Text("in \(meetingDate, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(meetingDate, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Counts badge
            let noteCount = (person.notes ?? []).count
            let followUpCount = (person.followUps ?? []).filter { !$0.isCompleted }.count
            if noteCount > 0 || followUpCount > 0 {
                HStack(spacing: 8) {
                    if noteCount > 0 {
                        Label("\(noteCount)", systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if followUpCount > 0 {
                        Label("\(followUpCount)", systemImage: "checklist")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
