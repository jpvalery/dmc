import SwiftUI

struct NotesPane: View {
    var notes: NotesStore
    var store: SceneStore
    var effects: EffectStore
    let onTrigger: (NoteTrigger) -> Void

    @State private var renaming: SessionNote?
    @State private var draftTitle = ""
    /// Reading mode makes the page uneditable and turns a plain click on a cue into "run it" —
    /// the way you want the notes while the table is playing, not while you are writing them.
    @AppStorage("notes.readMode") private var readMode = false

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

            linkMenu

            Button { readMode.toggle() } label: {
                Image(systemName: readMode ? "pencil" : "eye")
            }
            .buttonStyle(.borderless)
            .help(readMode ? "Edit the notes" : "Read mode: a click on a cue runs it")

            Button { notes.openToday() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Today's session  ⌘⌥N")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    /// Inserts a cue at the cursor, so a scene can be linked without typing its name out.
    private var linkMenu: some View {
        Menu {
            if !store.scenes.isEmpty {
                Section("Scene") {
                    ForEach(store.scenes) { scene in
                        Button(scene.name, systemImage: scene.symbol) {
                            notes.insert(NoteTrigger.scene(scene.name).markup)
                        }
                    }
                }
            }
            if !effects.effects.isEmpty {
                Section("Effect") {
                    ForEach(effects.effects) { effect in
                        Button(effect.name, systemImage: effect.symbol) {
                            notes.insert(NoteTrigger.effect(effect.name).markup)
                        }
                    }
                }
            }
            Section("Control") {
                Button("Stop all audio", systemImage: "stop.fill") {
                    notes.insert(NoteTrigger.stopAll.markup)
                }
            }
        } label: {
            Image(systemName: "link.badge.plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(notes.selected == nil || readMode)
        .help("Insert a cue that plays a scene or effect when clicked  (⌘-click while editing)")
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
                Text("Write [[scene:Tavern]] to make a cue you can click.")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            MarkdownEditor(notes: notes,
                           readOnly: readMode,
                           sceneNames: store.scenes.map(\.name),
                           effectNames: effects.effects.map(\.name),
                           onTrigger: onTrigger)
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
