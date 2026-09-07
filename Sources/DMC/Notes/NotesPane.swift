import SwiftUI

struct NotesPane: View {
    @ObservedObject var notes: NotesStore

    @State private var renaming: SessionNote?
    @State private var draftTitle = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(item: $renaming) { session in
            RenameSessionSheet(session: session, title: draftTitle) { newTitle in
                notes.rename(session, to: newTitle)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Menu {
                if notes.sessions.isEmpty {
                    Text("No sessions yet")
                } else {
                    ForEach(notes.sessions) { session in
                        Button {
                            notes.select(session)
                        } label: {
                            if session.id == notes.selected?.id {
                                Label(session.displayName, systemImage: "checkmark")
                            } else {
                                Text(session.displayName)
                            }
                        }
                    }
                }
                if let current = notes.selected {
                    Divider()
                    Button("Rename “\(current.title)”…") {
                        draftTitle = current.title == current.date ? "" : current.title
                        renaming = current
                    }
                    Button("Reveal in Finder") { Vault.reveal(current.url) }
                    Button("Delete “\(current.title)”", role: .destructive) {
                        notes.delete(current)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "note.text").font(.caption)
                    Text(notes.selected?.displayName ?? "Notes")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 0)

            statusLabel

            Button { notes.openToday() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Today's session  ⌘⌥N")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch notes.status {
        case .idle:
            EmptyView()
        case .editing:
            Text("saving…").font(.caption2).foregroundStyle(.tertiary)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green.opacity(0.7))
                .help("Saved")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help(message)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if notes.selected == nil {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "note.text").font(.largeTitle).foregroundStyle(.tertiary)
                Text("No session open").font(.callout).foregroundStyle(.secondary)
                Button("Start today's session") { notes.openToday() }
                Text("Plain markdown in this campaign's notes folder.")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            TextEditor(text: $notes.text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .focused($editorFocused)
        }
    }
}

private struct RenameSessionSheet: View {
    let session: SessionNote
    @State var title: String
    let onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename session").font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            Text("The date stays in the filename, so sessions keep sorting chronologically. "
                 + "Leave it empty to go back to just the date.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Rename") { commit() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func commit() {
        onRename(title)
        dismiss()
    }
}
