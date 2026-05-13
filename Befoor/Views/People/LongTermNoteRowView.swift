import SwiftUI

struct LongTermNoteRowView: View {
    let note: LongTermNote
    @State private var showEdit = false

    var body: some View {
        Button {
            showEdit = true
        } label: {
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
        .buttonStyle(.plain)
        .sheet(isPresented: $showEdit) {
            EditLongTermNoteView(note: note)
        }
    }
}
