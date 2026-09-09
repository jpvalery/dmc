import SwiftUI

/// A searchable, previewable, draggable view of everything in the vault.
///
/// Shared by the scene editor and anywhere else that needs to pick sounds: rows drag out as
/// vault-relative paths, and each can be auditioned in place rather than guessing from a filename.
struct SoundLibraryList: View {
    @ObservedObject var library: SoundLibrary
    @ObservedObject var engine: SceneEngine
    var onPick: ((SoundFile) -> Void)?

    @State private var search = ""

    /// The payload keys drag-and-drop; distinct from the hotkey payloads so a stray drop of one
    /// onto the other is refused rather than misread.
    static let dragPrefix = "sound:"

    private var matches: [SoundFile] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return library.files }
        return library.files.filter {
            $0.name.lowercased().contains(needle) || $0.folder.lowercased().contains(needle)
        }
    }

    private var grouped: [(folder: String, files: [SoundFile])] {
        Dictionary(grouping: matches, by: \.displayFolder)
            .map { (folder: $0.key, files: $0.value) }
            .sorted { $0.folder.localizedStandardCompare($1.folder) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Sound library").font(.callout.weight(.medium))
                    if library.isScanning { ProgressView().controlSize(.small) }
                    Spacer()
                    Text("\(library.files.count)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
                TextField("Search sounds and folders", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(12)
            Divider()

            if library.files.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform.slash").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Nothing in ~/DMConsole/audio yet")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(grouped, id: \.folder) { group in
                        Section(group.folder) {
                            ForEach(group.files) { file in row(file) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func row(_ file: SoundFile) -> some View {
        let isPreviewing = engine.previewing == file.relativePath
        return HStack(spacing: 6) {
            Button {
                engine.preview(file.relativePath)
            } label: {
                Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isPreviewing ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isPreviewing ? "Stop" : "Preview")

            VStack(alignment: .leading, spacing: 0) {
                Text(file.name).font(.caption).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(file.durationText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            if onPick != nil {
                Button { onPick?(file) } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add")
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .draggable(Self.dragPrefix + file.relativePath) {
            Label(file.name, systemImage: "waveform")
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}
