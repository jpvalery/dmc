import SwiftUI

/// Multi-select over everything in the vault, grouped by folder.
struct SoundPicker: View {
    @ObservedObject var library: SoundLibrary
    let onAdd: ([SoundFile]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selected: Set<String> = []

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
        VStack(spacing: 0) {
            HStack {
                Text("Add sounds").font(.headline)
                if library.isScanning { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add \(selected.count > 0 ? "\(selected.count)" : "")") {
                    onAdd(library.files.filter { selected.contains($0.relativePath) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding(12)

            TextField("Search the library", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            if library.files.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform.slash").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No audio in the vault yet")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Add files to ~/DMConsole/audio, or download ambiences\nfrom Tabletop Audio.")
                        .font(.caption).multilineTextAlignment(.center).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(grouped, id: \.folder) { group in
                        Section(group.folder) {
                            ForEach(group.files) { file in
                                Toggle(isOn: Binding(
                                    get: { selected.contains(file.relativePath) },
                                    set: { on in
                                        if on { selected.insert(file.relativePath) }
                                        else { selected.remove(file.relativePath) }
                                    }
                                )) {
                                    HStack {
                                        Text(file.name).lineLimit(1)
                                        Spacer()
                                        Text(file.durationText)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 520, height: 480)
    }
}
