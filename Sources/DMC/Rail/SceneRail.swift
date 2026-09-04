import SwiftUI

struct SceneRail: View {
    @ObservedObject var engine: SceneEngine
    @ObservedObject var store: SceneStore
    let collapsed: Bool
    @ObservedObject var campaigns: CampaignStore
    @ObservedObject var router: UIRouter
    @ObservedObject var effects: EffectStore
    let onNew: () -> Void
    let onEdit: (SoundScene) -> Void
    let onNewEffect: () -> Void
    let onEditEffect: (SoundEffect) -> Void
    let onBrowse: () -> Void

    @State private var showVolumePopover = false
    /// The scene a drag would land in front of; nil while nothing is hovered.
    @State private var dropTarget: UUID?
    @State private var dropAtEnd = false
    @State private var effectDropTarget: UUID?
    @State private var firedEffect: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 4) {
                    if store.scenes.isEmpty && effects.effects.isEmpty {
                        emptyState
                    } else {
                        sectionHeader("Scenes", systemImage: "waveform", action: onNew)
                        ForEach(Array(store.scenes.enumerated()), id: \.element.id) { index, scene in
                            reorderable(scene, shortcutIndex: index)
                        }
                        endDropZone

                        sectionHeader("Effects", systemImage: "bolt.fill", action: onNewEffect)
                        if effects.effects.isEmpty {
                            if !collapsed {
                                Text("One-shot sounds you fire over a scene.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.vertical, 4)
                            }
                        } else {
                            ForEach(effects.effects) { effect in
                                effectRow(effect)
                            }
                        }
                    }
                }
                .padding(6)
            }

            if !collapsed { problemsSection }

            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Sections

    /// Collapses to a hairline when the rail is icon-only — a text label would not fit, but the
    /// two groups still need separating.
    private func sectionHeader(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Group {
            if collapsed {
                Divider().padding(.vertical, 4)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: systemImage).font(.system(size: 9))
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                    Spacer()
                    if title == "Scenes" {
                        Button { router.showTemplates = true } label: {
                            Image(systemName: "square.grid.2x2").font(.system(size: 9))
                        }
                        .buttonStyle(.borderless)
                        .help("Scene templates  ⌘⇧T")
                    }
                    Button(action: action) { Image(systemName: "plus").font(.system(size: 9)) }
                        .buttonStyle(.borderless)
                        .help("New \(title.lowercased())")
                }
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.horizontal, 2)
            }
        }
    }

    private func effectRow(_ effect: SoundEffect) -> some View {
        let sounding = engine.isSounding(effect.id)
        let copies = engine.soundingEffects[effect.id] ?? 0

        // Not a Button: the row needs its own stop button inside it, and SwiftUI will not nest
        // one button in another. A tap gesture on the fire area does the same job.
        return HStack(spacing: 6) {
            HStack(spacing: 8) {
                // Collapsed there is no room for a separate control, so the icon itself becomes
                // the stop button while the effect sounds.
                Image(systemName: (collapsed && sounding) ? "stop.fill" : effect.symbol)
                    .font(.system(size: collapsed ? 16 : 13))
                    .frame(width: collapsed ? 28 : 18)
                    .foregroundStyle(collapsed && sounding ? Color.accentColor : Color.primary)

                if !collapsed {
                    Text(effect.name).font(.caption).lineLimit(1)
                    if copies > 1 {
                        Text("\(copies)")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.25))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                    if effect.isMissing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if collapsed && sounding {
                    engine.stopEffect(effect.id)
                } else {
                    engine.fire(effect)
                    firedEffect = effect.id
                    Task {
                        try? await Task.sleep(for: .milliseconds(220))
                        if firedEffect == effect.id { firedEffect = nil }
                    }
                }
            }

            if !collapsed && sounding {
                Button { engine.stopEffect(effect.id) } label: {
                    Image(systemName: "stop.fill").font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Stop this effect")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, collapsed ? 0 : 6)
        .frame(maxWidth: .infinity)
        .background(
            sounding ? Color.accentColor.opacity(0.18)
                     : (firedEffect == effect.id ? Color.accentColor.opacity(0.35) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(effect.isMissing ? 0.5 : 1)
        .help(sounding ? "\(effect.name) — playing, click to stop" : effect.name)
        .overlay(alignment: .top) { insertionLine(visible: effectDropTarget == effect.id) }
        .draggable(effect.id.uuidString) {
            Label(effect.name, systemImage: effect.symbol)
                .padding(6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { items, _ in
            effectDropTarget = nil
            guard let raw = items.first, let id = UUID(uuidString: raw), effects.contains(id)
            else { return false }
            effects.move(id, before: effect.id)
            return true
        } isTargeted: { targeted in
            if targeted { effectDropTarget = effect.id }
            else if effectDropTarget == effect.id { effectDropTarget = nil }
        }
        .contextMenu {
            if sounding { Button("Stop") { engine.stopEffect(effect.id) } }
            Button("Edit…") { onEditEffect(effect) }
            Divider()
            Button("Delete", role: .destructive) { effects.delete(effect) }
        }
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
                Button("Scene templates…") { router.showTemplates = true }
                    .buttonStyle(.link).font(.caption)
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

                    Button { engine.togglePlayPause() } label: {
                        Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!engine.isPlaying)
                    .help(engine.isPaused ? "Resume" : "Pause")

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
                    HStack(spacing: 6) {
                        Button {
                            engine.togglePlayPause()
                        } label: {
                            Label(engine.isPaused ? "Resume" : "Pause",
                                  systemImage: engine.isPaused ? "play.fill" : "pause.fill")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!engine.isPlaying)

                        Button {
                            engine.stopAll()
                        } label: {
                            Label("Stop all", systemImage: "stop.fill")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!engine.isPlaying)
                    }
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
