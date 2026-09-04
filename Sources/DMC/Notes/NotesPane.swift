import SwiftUI

/// Phase 1 placeholder: real campaign/session pickers and debounced autosave land in phase 4.
struct NotesPane: View {
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("phase 4").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)

            Divider()

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
