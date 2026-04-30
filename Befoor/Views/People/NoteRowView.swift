import SwiftUI

struct NoteRowView: View {
    let note: Note
    var showGlobalBadge: Bool = false
    @State private var showEdit = false

    var body: some View {
        Button {
            showEdit = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(note.meetingDate, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.indigo)

                    if showGlobalBadge {
                        Text("Everyone")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.indigo.opacity(0.7), in: Capsule())
                    }
                }

                Text(note.text)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEdit) {
            EditNoteView(note: note)
        }
    }
}
