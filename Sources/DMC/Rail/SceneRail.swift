import SwiftUI

struct SceneRail: View {
    @ObservedObject var engine: SceneEngine
    @ObservedObject var store: SceneStore
    let collapsed: Bool
    @ObservedObject var campaigns: CampaignStore
    @ObservedObject var router: UIRouter
    let onNew: () -> Void
    let onEdit: (SoundScene) -> Void
    let onBrowse: () -> Void

    @State private var showVolumePopover = false
    /// The scene a drag would land in front of; nil while nothing is hovered.
    @State private var dropTarget: UUID?
    @State private var dropAtEnd = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.scenes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(store.scenes.enumerated()), id: \.element.id) { index, scene in
                            reorderable(scene, shortcutIndex: index)
                        }
                        endDropZone
                    }
                    .padding(6)
                }
            }

            if !collapsed { problemsSection }

            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Reordering

    /// Drag to reorder. Order is not cosmetic — it drives ⌘1–⌘9 and "Assign scenes in order"
    /// on the macropad, so putting the scenes you reach for first at the top actually matters.
    private func reorderable(_ scene: SoundScene, shortcutIndex: Int) -> some View {
        sceneButton(scene, shortcutIndex: shortcutIndex)
            .opacity(dropTarget == scene.id ? 0.75 : 1)
            .overlay(alignment: .top) { insertionLine(visible: dropTarget == scene.id) }
            .draggable(scene.id.uuidString) {
                Label(scene.name, systemImage: scene.symbol)
                    .padding(6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .dropDestination(for: String.self) { items, _ in
                dropTarget = nil
                return accept(items, before: scene.id)
            } isTargeted: { targeted in
                if targeted { dropTarget = scene.id }
                else if dropTarget == scene.id { dropTarget = nil }
            }
    }

    /// A short strip under the last scene, so something can be dragged to the very end.
    private var endDropZone: some View {
        Color.clear
            .frame(height: 20)
            .overlay(alignment: .top) { insertionLine(visible: dropAtEnd) }
            .dropDestination(for: String.self) { items, _ in
                dropAtEnd = false
                return accept(items, before: nil)
            } isTargeted: { dropAtEnd = $0 }
    }

    private func insertionLine(visible: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .opacity(visible ? 1 : 0)
    }

    /// Only our own scene drags are honoured; stray text dropped on the rail is ignored.
    private func accept(_ items: [String], before target: UUID?) -> Bool {
        guard let raw = items.first,
              let id = UUID(uuidString: raw),
              store.contains(id)
        else { return false }
        store.move(id, before: target)
        return true
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 4) {
            if !collapsed {
                Text("Scenes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            CampaignMenu(campaigns: campaigns, router: router, collapsed: collapsed)
            if !collapsed { Spacer(minLength: 0) }
            Button(action: onNew) { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("New scene")
            if !collapsed {
                Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Reload scenes")
            }
            if collapsed { Spacer(minLength: 0) }
        }
        .padding(.horizontal, collapsed ? 0 : 10)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
    }

    private func sceneButton(_ scene: SoundScene, shortcutIndex: Int) -> some View {
        let isActive = engine.activeSceneID == scene.id
        let shortcut = shortcutIndex < 9 ? "  ⌘\(shortcutIndex + 1)" : ""

        return Button {
            engine.toggle(scene)
        } label: {
            Group {
                if collapsed {
                    Image(systemName: scene.symbol)
                        .font(.system(size: 17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: scene.symbol)
                            .font(.system(size: 15))
                            .frame(width: 22)
                        Text(scene.name).font(.callout).lineLimit(1)
                        Spacer(minLength: 0)
                        if isActive {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                }
            }
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .background(isActive ? Color.accentColor.opacity(0.18) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("\(scene.name) — \(scene.layers.count) sound\(scene.layers.count == 1 ? "" : "s")\(shortcut)")
        .contextMenu {
            Button("Edit…") { onEdit(scene) }
            Button("Duplicate") { store.duplicate(scene) }
            Divider()
            Button("Delete", role: .destructive) {
                if engine.activeSceneID == scene.id { engine.stopAll() }
                store.delete(scene)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: collapsed ? 18 : 24))
                .foregroundStyle(.tertiary)
            if !collapsed {
                Text("No scenes yet")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Each folder inside\n~/DMConsole/audio\nbecomes a scene.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                Button("Browse Tabletop Audio…", action: onBrowse)
                    .buttonStyle(.link).font(.caption)
                Button("New scene…", action: onNew)
                    .buttonStyle(.link).font(.caption)
                Button("Open folder") { Vault.reveal(Vault.audio) }
                    .buttonStyle(.link).font(.caption)
            }
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity)
    }

    private var problemsSection: some View {
        let messages = engine.problems + store.unplayable.map {
            "\($0) — can't be decoded by macOS; convert to .m4a, .flac or .wav."
        }
        return Group {
            if !messages.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(messages, id: \.self) { message in
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                                Text(message).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }
        }
    }

    private var footer: some View {
        Group {
            if collapsed {
                VStack(spacing: 6) {
                    Button { showVolumePopover = true } label: {
                        Image(systemName: speakerSymbol)
                    }
                    .buttonStyle(.borderless)
                    .help("Master volume")
                    .popover(isPresented: $showVolumePopover) {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill").font(.caption)
                            Slider(value: $engine.masterVolume, in: 0...1).frame(width: 130)
                            Image(systemName: "speaker.wave.3.fill").font(.caption)
                        }
                        .padding(12)
                    }

                    Button { engine.stopAll() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(.borderless)
                        .disabled(!engine.isPlaying)
                        .help("Stop all  ⌘0")
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: speakerSymbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Slider(value: $engine.masterVolume, in: 0...1)
                    }
                    Button {
                        engine.stopAll()
                    } label: {
                        Label("Stop all", systemImage: "stop.fill")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!engine.isPlaying)
                }
                .padding(8)
            }
        }
    }

    private var speakerSymbol: String {
        if engine.masterVolume < 0.01 { return "speaker.slash.fill" }
        if engine.masterVolume < 0.4 { return "speaker.wave.1.fill" }
        if engine.masterVolume < 0.75 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
