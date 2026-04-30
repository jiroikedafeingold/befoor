import SwiftUI

struct LongTermNoteRowView: View {
    let note: LongTermNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.text)
                .font(.body)
                .lineLimit(3)

            Text("Added \(note.createdAt, format: .dateTime.month().day().year())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
