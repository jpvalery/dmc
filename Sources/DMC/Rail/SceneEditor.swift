import SwiftUI

struct SceneEditor: View {
    @State var scene: SoundScene
    let isNew: Bool
    @ObservedObject var library: SoundLibrary
    @ObservedObject var engine: SceneEngine
    let onSave: (SoundScene) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSymbols = false
    @State private var bindingSlot: AudioLayer.ID?
    @State private var isDropTargeted = false

    private var isAuditioning: Bool { engine.activeSceneID == scene.id }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                layerList
                Divider()
                footer
            }
            .frame(minWidth: 520, idealWidth: 620)

            SoundLibraryList(library: library, engine: engine) { file in
                append(file.relativePath)
            }
            .frame(minWidth: 260, idealWidth: 320)
        }
        .frame(minWidth: 860, minHeight: 560)
        .frame(idealWidth: 1020, idealHeight: 680)
        .sheet(isPresented: $showSymbols) { SymbolPicker(selection: $scene.symbol) }
        .sheet(item: $bindingSlot) { slotID in
            SoundPicker(library: library, engine: engine) { files in
                guard let file = files.first,
                      let index = scene.layers.firstIndex(where: { $0.id == slotID }) else { return }
                scene.layers[index].file = file.relativePath
                engine.refreshIfPlaying(scene)
            }
        }
        .onDisappear { engine.stopPreview() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { showSymbols = true } label: {
                Image(systemName: scene.symbol)
                    .font(.system(size: 22))
                    .frame(width: 46, height: 46)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .help("Change icon")

            VStack(alignment: .leading, spacing: 3) {
                TextField("Scene name", text: $scene.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                Text("\(scene.layers.count) layer\(scene.layers.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var layerList: some View {
        Group {
            if scene.layers.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Drag sounds in from the right")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Or press ▶ there to hear one first.")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach($scene.layers) { $layer in
                        LayerRow(layer: $layer,
                                 engine: engine,
                                 isAuditioning: isAuditioning,
                                 onBind: { bindingSlot = layer.id },
                                 onRemove: {
                                     scene.layers.removeAll { $0.id == layer.id }
                                     engine.refreshIfPlaying(scene)
                                 })
                    }
                    .onMove { from, to in scene.layers.move(fromOffsets: from, toOffset: to) }
                }
                .listStyle(.inset)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            let paths = items.compactMap { item -> String? in
                guard item.hasPrefix(SoundLibraryList.dragPrefix) else { return nil }
                return String(item.dropFirst(SoundLibraryList.dragPrefix.count))
            }
            guard !paths.isEmpty else { return false }
            paths.forEach(append)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private func append(_ relativePath: String) {
        scene.layers.append(AudioLayer(file: relativePath))
        engine.refreshIfPlaying(scene)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                fadeField("Fade in", value: $scene.fadeIn)
                fadeField("Fade out", value: $scene.fadeOut)
                Spacer()
                Button {
                    isAuditioning ? engine.stopAll() : engine.play(scene)
                } label: {
                    Label(isAuditioning ? "Stop" : "Audition",
                          systemImage: isAuditioning ? "stop.fill" : "play.fill")
                }
                .disabled(scene.layers.isEmpty)
                .help("Hear the whole scene while you set levels")
            }

            HStack {
                if !isNew {
                    Button(role: .destructive) {
                        engine.stopAll()
                        onDelete()
                        dismiss()
                    } label: { Text("Delete") }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isNew ? "Create" : "Save") {
                    onSave(scene)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(scene.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func fadeField(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Stepper(value: value, in: 0...15, step: 0.5) {
                Text(String(format: "%.1fs", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

private struct LayerRow: View {
    @Binding var layer: AudioLayer
    @ObservedObject var engine: SceneEngine
    let isAuditioning: Bool
    let onBind: () -> Void
    let onRemove: () -> Void

    private var isMissing: Bool {
        layer.isBound && !FileManager.default.fileExists(atPath: layer.url.path)
    }
    private var isPreviewing: Bool { engine.previewing == layer.file }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if layer.isBound {
                    Button { engine.preview(layer.file, gain: layer.gain) } label: {
                        Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(isPreviewing ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isPreviewing ? "Stop" : "Preview this layer alone")
                }

                if !layer.isBound {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Slot \(layer.padID ?? "—")")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Choose sound…", action: onBind)
                        .buttonStyle(.link).font(.caption)
                } else {
                    if isMissing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                            .help("This file is no longer in the vault")
                    }
                    Text((layer.file as NSString).lastPathComponent)
                        .font(.callout).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Toggle("Loop", isOn: $layer.loops)
                    .toggleStyle(.checkbox).font(.caption)
                    .disabled(layer.sporadic)
                Toggle("Sporadic", isOn: $layer.sporadic)
                    .toggleStyle(.checkbox).font(.caption)
                    .help("Fire at random intervals instead of looping")
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }

            if layer.sporadic {
                HStack(spacing: 4) {
                    Image(systemName: "dice").font(.caption2).foregroundStyle(.secondary)
                    Text("every").font(.caption2).foregroundStyle(.secondary)
                    Stepper(value: $layer.minGap, in: 1...300, step: 1) {
                        Text("\(Int(layer.minGap))s").font(.caption2.monospacedDigit())
                            .frame(width: 30, alignment: .trailing)
                    }
                    Text("to").font(.caption2).foregroundStyle(.secondary)
                    Stepper(value: $layer.maxGap, in: 1...300, step: 1) {
                        Text("\(Int(layer.maxGap))s").font(.caption2.monospacedDigit())
                            .frame(width: 30, alignment: .trailing)
                    }
                    if !layer.variants.isEmpty {
                        Text("· \(layer.variants.count + 1) variants")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                // Live: moving this while the scene sounds retunes the mix immediately, which
                // is the only sane way to balance layers.
                Slider(value: $layer.gain, in: 0...1) { editing in
                    if !editing { applyLive() }
                }
                .onChange(of: layer.gain) { _, _ in applyLive() }
                Text(String(format: "%3d%%", Int(layer.gain * 100)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
        .opacity(isMissing || !layer.isBound ? 0.6 : 1)
    }

    private func applyLive() {
        guard isAuditioning else { return }
        engine.setLiveGain(layer.gain, forLayer: layer.id)
    }
}
