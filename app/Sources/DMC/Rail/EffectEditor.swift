import SwiftUI

struct EffectEditor: View {
    @State var effect: SoundEffect
    let isNew: Bool
    var library: SoundLibrary
    var engine: SceneEngine
    let onSave: (SoundEffect) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSymbols = false
    @State private var showSounds = false

    private var hasFile: Bool { !effect.file.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { showSymbols = true } label: {
                    Image(systemName: effect.symbol)
                        .font(.system(size: 20))
                        .frame(width: 42, height: 42)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help("Change icon")

                TextField("Effect name", text: $effect.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Sound").font(.caption).foregroundStyle(.secondary)
                HStack {
                    if hasFile {
                        if effect.isMissing {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                                .help("This file is no longer in the vault")
                        }
                        Text((effect.file as NSString).lastPathComponent)
                            .font(.callout).lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("None chosen").font(.callout).foregroundStyle(.tertiary)
                    }
                    if !effect.variants.isEmpty {
                        Text("+\(effect.variants.count) takes")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(hasFile ? "Change…" : "Choose…") { showSounds = true }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Level").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $effect.gain, in: 0...1)
                    Text(String(format: "%3d%%", Int(effect.gain * 100)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Lower the scene while this plays", isOn: Binding(
                    get: { effect.duck > 0 },
                    set: { effect.duck = $0 ? 0.5 : 0 }
                ))
                .toggleStyle(.checkbox)
                .help("Pulls the scene's ambience down under the effect, then eases it back")

                if effect.duck > 0 {
                    Picker("", selection: $effect.duck) {
                        Text("Slightly").tag(0.3)
                        Text("Clearly").tag(0.5)
                        Text("Heavily").tag(0.75)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
            }

            // Effects are short, so auditioning is just firing it — no transport needed.
            Button {
                engine.fire(effect)
            } label: {
                Label("Test", systemImage: "play.fill")
            }
            .disabled(!hasFile || effect.isMissing)

            Spacer(minLength: 0)

            HStack {
                if !isNew {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: { Text("Delete") }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isNew ? "Create" : "Save") {
                    onSave(effect)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasFile || effect.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 480, height: 440)
        .onDisappear { engine.stopPreview() }
        .sheet(isPresented: $showSymbols) { SymbolPicker(selection: $effect.symbol) }
        .sheet(isPresented: $showSounds) {
            SoundPicker(library: library, engine: engine) { files in
                if let file = files.first {
                    effect.file = file.relativePath
                    if effect.name.trimmingCharacters(in: .whitespaces).isEmpty { effect.name = file.name }
                }
            }
        }
    }
}
