import AppKit
import SwiftUI

/// The physical shape of the Winry315 on this desk: three encoders above a 5x3 grid.
///
/// Only the first four columns reach DMC — the fifth sends KC_F/KC_R/KC_X, which are not
/// function keys and so are not hotkey slots. They are drawn anyway, because a mapper that
/// silently omits three real keys is a mapper you cannot trust.
enum PadSpec {
    struct Key: Identifiable {
        let id: Int
        /// nil when the key sends something DMC never sees.
        let slot: Int?
        let label: String
        let via: String
    }

    /// Row-major, as the keys sit on the desk.
    static let grid: [[Key]] = {
        var out: [[Key]] = []
        var id = 0
        let banks: [(slotBase: Int, prefix: String, wrap: (String) -> String)] = [
            (0,  "",  { $0 }),
            (8,  "⇧", { "LSFT(\($0))" }),
            (16, "⌃", { "LCTL(\($0))" }),
        ]
        let spare = ["KC_F", "KC_R", "KC_X"]
        for (row, bank) in banks.enumerated() {
            var line: [Key] = []
            for column in 0..<4 {
                let name = "F\(13 + column)"
                line.append(Key(id: id, slot: bank.slotBase + column,
                                label: bank.prefix + name, via: bank.wrap("KC_\(name)")))
                id += 1
            }
            let raw = spare[row]
            line.append(Key(id: id, slot: nil, label: String(raw.dropFirst(3)), via: raw))
            id += 1
            out.append(line)
        }
        return out
    }()

    struct Encoder: Identifiable {
        let id: String
        let name: String
        /// Slots for counter-clockwise, clockwise and press; nil where DMC never hears it.
        let ccw: Int?
        let cw: Int?
        let press: Int?
        /// Shown instead of bindings when the knob acts on the host or the board itself.
        let fixed: (ccw: String, cw: String, press: String)?
    }

    /// The left knob is the only encoder DMC hears; the other two act on the host or the board.
    static let encoders: [Encoder] = [
        .init(id: "L", name: "Left",   ccw: 5, cw: 4, press: 6, fixed: nil),
        .init(id: "C", name: "Centre", ccw: nil, cw: nil, press: nil,
              fixed: ("scroll ↓", "scroll ↑", "middle click")),
        .init(id: "R", name: "Right",  ccw: nil, cw: nil, press: nil,
              fixed: ("dimmer", "brighter", "RGB mode")),
    ]
}

struct PadMapper: View {
    @ObservedObject var hotkeys: HotkeyManager
    @ObservedObject var store: SceneStore
    @ObservedObject var effects: EffectStore

    @State private var selectedSlot: Int?
    @State private var dropSlot: Int?
    @State private var search = ""
    @State private var copied = false

    var body: some View {
        HSplitView {
            padSide
                .frame(minWidth: 560, idealWidth: 640)
            librarySide
                .frame(minWidth: 260, idealWidth: 320)
        }
        .frame(minWidth: 880, minHeight: 620)
    }

    // MARK: - Left: the pad itself

    private var padSide: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    encoderRow
                    gridView
                    assignment
                }
                .padding(18)
            }
            Divider()
            footer
        }
    }

    private var encoderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ENCODERS")
            HStack(spacing: 12) {
                ForEach(PadSpec.encoders) { knob($0) }
            }
        }
    }

    private func knob(_ encoder: PadSpec.Encoder) -> some View {
        VStack(spacing: 8) {
            Text(encoder.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                rotation(slot: encoder.ccw, fixed: encoder.fixed?.ccw, glyph: "arrow.counterclockwise")
                press(slot: encoder.press, fixed: encoder.fixed?.press)
                rotation(slot: encoder.cw, fixed: encoder.fixed?.cw, glyph: "arrow.clockwise")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func rotation(slot: Int?, fixed: String?, glyph: String) -> some View {
        let selected = slot != nil && slot == selectedSlot
        let hovered = slot != nil && slot == dropSlot
        return VStack(spacing: 3) {
            Image(systemName: glyph)
                .font(.system(size: 11))
                .foregroundStyle(slot == nil ? .tertiary : .secondary)
            Text(slot.map { describe(hotkeys.binding(for: HotkeySlot.all[$0])) } ?? (fixed ?? "—"))
                .font(.system(size: 10))
                .foregroundStyle(slot == nil ? .tertiary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .padding(5)
        .background(hovered ? Color.accentColor.opacity(0.35)
                            : (selected ? Color.accentColor.opacity(0.22)
                                        : Color(nsColor: .controlBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { if let slot { selectedSlot = slot } }
        .modifier(SlotDropTarget(slot: slot, hovered: $dropSlot, assign: assign))
    }

    private func press(slot: Int?, fixed: String?) -> some View {
        let selected = slot != nil && slot == selectedSlot
        let hovered = slot != nil && slot == dropSlot
        return VStack(spacing: 4) {
            Circle()
                .strokeBorder(selected || hovered ? Color.accentColor
                                                  : Color(nsColor: .separatorColor),
                              lineWidth: selected || hovered ? 2.5 : 1)
                .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: slot.map { glyph(for: hotkeys.binding(for: HotkeySlot.all[$0])) }
                                          ?? "hand.tap")
                        .font(.system(size: 16))
                        .foregroundStyle(slot == nil ? .tertiary : .primary)
                }
            Text(slot.map { describe(hotkeys.binding(for: HotkeySlot.all[$0])) } ?? (fixed ?? "—"))
                .font(.system(size: 9))
                .foregroundStyle(slot == nil ? .tertiary : .secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { if let slot { selectedSlot = slot } }
        .modifier(SlotDropTarget(slot: slot, hovered: $dropSlot, assign: assign))
    }

    private var gridView: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("KEYS")
            VStack(spacing: 8) {
                ForEach(Array(PadSpec.grid.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { keyCell($0) }
                    }
                }
            }
        }
    }

    private func keyCell(_ key: PadSpec.Key) -> some View {
        let action = key.slot.map { hotkeys.binding(for: HotkeySlot.all[$0]) } ?? .none
        let selected = key.slot != nil && key.slot == selectedSlot
        let hovered = key.slot != nil && key.slot == dropSlot
        let dead = key.slot == nil

        return Button {
            if let slot = key.slot { selectedSlot = slot }
        } label: {
            VStack(spacing: 5) {
                Text(key.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                // The bound thing's own icon, so the pad reads like the rail does.
                Image(systemName: dead ? "minus" : glyph(for: action))
                    .font(.system(size: 20))
                    .foregroundStyle(dead ? .tertiary
                                          : (action == .none ? .tertiary : .primary))
                Text(dead ? "not a hotkey" : describe(action))
                    .font(.system(size: 11))
                    .foregroundStyle(dead ? .tertiary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 92)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .background(hovered ? Color.accentColor.opacity(0.4)
                                : (selected ? Color.accentColor.opacity(0.24)
                                   : (dead ? Color(nsColor: .windowBackgroundColor)
                                           : Color(nsColor: .controlBackgroundColor))))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(hovered || selected ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: hovered ? 2.5 : (selected ? 2 : 0.5))
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(dead)
        .modifier(SlotDropTarget(slot: key.slot, hovered: $dropSlot, assign: assign))
        .help(dead ? "\(key.via) — remap it in VIA to F20 to reach DMC"
                   : "\(key.via) — click to bind, or drop something here")
    }

    @ViewBuilder
    private var assignment: some View {
        if let slot = selectedSlot {
            let padSlot = HotkeySlot.all[slot]
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(padSlot.label)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                    Text(padSlot.viaCode)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Clear") { hotkeys.setBinding(.none, for: padSlot) }
                        .disabled(hotkeys.binding(for: padSlot) == .none)
                }
                ActionPicker(selection: Binding(
                    get: { hotkeys.binding(for: padSlot) },
                    set: { hotkeys.setBinding($0, for: padSlot) }
                ), store: store, effects: effects)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        } else {
            Text("Click a key or knob to bind it, or drag something from the right.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Match macropad") {
                for slot in HotkeySlot.all { hotkeys.setBinding(.none, for: slot) }
                for (index, action) in HotkeyManager.padLayout {
                    hotkeys.setBinding(action, for: HotkeySlot.all[index])
                }
            }
            .help("Restore the default layout for this pad")
            Button("Clear all") {
                for slot in HotkeySlot.all { hotkeys.setBinding(.none, for: slot) }
            }
            Button(copied ? "Copied" : "Copy VIA sheet") { copyCheatSheet() }
            Spacer()
            Text("Set each key to Any in VIA and paste its code.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    // MARK: - Right: the searchable library

    private var librarySide: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drag onto a key or knob")
                    .font(.callout.weight(.medium))
                TextField("Search scenes and effects", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(12)
            Divider()

            List {
                if !matchingScenes.isEmpty {
                    Section("Scenes") {
                        ForEach(matchingScenes, id: \.0) { position, name, symbol, action in
                            libraryRow(position: position, name: name, symbol: symbol, action: action)
                        }
                    }
                }
                if !matchingEffects.isEmpty {
                    Section("Effects") {
                        ForEach(matchingEffects, id: \.0) { position, name, symbol, action in
                            libraryRow(position: position, name: name, symbol: symbol, action: action)
                        }
                    }
                }
                if matchingActions.count > 0 {
                    Section("Controls") {
                        ForEach(matchingActions, id: \.0) { label, glyph, action in
                            libraryRow(position: nil, name: label, symbol: glyph, action: action)
                        }
                    }
                }
                if matchingScenes.isEmpty && matchingEffects.isEmpty && matchingActions.isEmpty {
                    Text("Nothing matches “\(search)”")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }

    private func libraryRow(position: Int?, name: String, symbol: String,
                            action: HotkeyAction) -> some View {
        HStack(spacing: 7) {
            if let position {
                Text("\(position)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, alignment: .trailing)
            } else {
                Spacer().frame(width: 14)
            }
            Image(systemName: symbol).font(.system(size: 12))
                .foregroundStyle(.secondary).frame(width: 16)
            Text(name).font(.callout).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .draggable(action.dragPayload) {
            Label(name, systemImage: symbol)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var needle: String { search.trimmingCharacters(in: .whitespaces).lowercased() }

    private func hit(_ text: String) -> Bool { needle.isEmpty || text.lowercased().contains(needle) }

    private var matchingScenes: [(Int, String, String, HotkeyAction)] {
        store.scenes.enumerated().compactMap { index, scene in
            hit(scene.name) ? (index + 1, scene.name, scene.symbol, .scene(scene.id)) : nil
        }
    }

    private var matchingEffects: [(Int, String, String, HotkeyAction)] {
        effects.effects.enumerated().compactMap { index, effect in
            hit(effect.name) ? (index + 1, effect.name, effect.symbol, .effect(effect.id)) : nil
        }
    }

    private var matchingActions: [(String, String, HotkeyAction)] {
        [("Pause / resume", "playpause.fill", HotkeyAction.togglePlayPause),
         ("Stop all", "stop.fill", .stopAll),
         ("Mute / unmute", "speaker.slash.fill", .toggleMute),
         ("Volume up", "speaker.wave.2.fill", .volumeUp),
         ("Volume down", "speaker.fill", .volumeDown),
         ("Next scene", "forward.fill", .nextScene),
         ("Previous scene", "backward.fill", .previousScene),
         ("New scene", "plus", .newScene)]
            .filter { hit($0.0) }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold)).tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private func assign(_ payload: String, to slot: Int) -> Bool {
        guard let action = HotkeyAction.fromDragPayload(payload) else { return false }
        hotkeys.setBinding(action, for: HotkeySlot.all[slot])
        selectedSlot = slot
        return true
    }

    /// A key shows the icon of whatever it fires, so the pad reads like the rail.
    private func glyph(for action: HotkeyAction) -> String {
        switch action {
        case .none: "circle.dashed"
        case .stopAll: "stop.fill"
        case .togglePlayPause: "playpause.fill"
        case .toggleMute: "speaker.slash.fill"
        case .volumeUp: "speaker.wave.2.fill"
        case .volumeDown: "speaker.fill"
        case .nextScene: "forward.fill"
        case .previousScene: "backward.fill"
        case .newScene: "plus"
        case .sceneIndex(let n):
            store.scenes.indices.contains(n - 1) ? store.scenes[n - 1].symbol : "waveform"
        case .effectIndex(let n):
            effects.effects.indices.contains(n - 1) ? effects.effects[n - 1].symbol : "bolt.fill"
        case .scene(let id): store.scenes.first { $0.id == id }?.symbol ?? "waveform"
        case .effect(let id): effects.effects.first { $0.id == id }?.symbol ?? "bolt.fill"
        }
    }

    private func describe(_ action: HotkeyAction) -> String {
        switch action {
        case .none: "—"
        case .stopAll: "Stop all"
        case .volumeUp: "Vol +"
        case .volumeDown: "Vol −"
        case .nextScene: "Next scene"
        case .previousScene: "Prev scene"
        case .newScene: "New scene"
        case .toggleMute: "Mute"
        case .togglePlayPause: "Pause"
        case .sceneIndex(let n):
            store.scenes.indices.contains(n - 1) ? store.scenes[n - 1].name : "Scene \(n)"
        case .effectIndex(let n):
            effects.effects.indices.contains(n - 1) ? effects.effects[n - 1].name : "Effect \(n)"
        case .scene(let id): store.scenes.first { $0.id == id }?.name ?? "(deleted scene)"
        case .effect(let id): effects.effects.first { $0.id == id }?.name ?? "(deleted effect)"
        }
    }

    private func copyCheatSheet() {
        var lines = ["DMC macropad mapping", "", "VIA code            Key    Action"]
        for slot in HotkeySlot.all {
            let action = hotkeys.binding(for: slot)
            guard action != .none else { continue }
            lines.append(slot.viaCode.padding(toLength: 20, withPad: " ", startingAt: 0)
                         + slot.label.padding(toLength: 7, withPad: " ", startingAt: 0)
                         + describe(action))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}



/// The action menu, used by the assignment panel.
struct ActionPicker: View {
    @Binding var selection: HotkeyAction
    @ObservedObject var store: SceneStore
    @ObservedObject var effects: EffectStore

    var body: some View {
        Picker("", selection: $selection) {
            Text("— nothing —").tag(HotkeyAction.none)
            Divider()
            Text("Stop all audio").tag(HotkeyAction.stopAll)
            Text("Pause / resume").tag(HotkeyAction.togglePlayPause)
            Text("Mute / unmute").tag(HotkeyAction.toggleMute)
            Text("Volume up").tag(HotkeyAction.volumeUp)
            Text("Volume down").tag(HotkeyAction.volumeDown)
            Text("Next scene").tag(HotkeyAction.nextScene)
            Text("Previous scene").tag(HotkeyAction.previousScene)
            Text("New scene…").tag(HotkeyAction.newScene)

            Section("Scene by position") {
                ForEach(1...max(16, store.scenes.count), id: \.self) { position in
                    let name = store.scenes.indices.contains(position - 1)
                        ? store.scenes[position - 1].name : "empty"
                    Text("\(position) — \(name)").tag(HotkeyAction.sceneIndex(position))
                }
            }
            Section("Effect by position") {
                ForEach(1...max(16, effects.effects.count), id: \.self) { position in
                    let name = effects.effects.indices.contains(position - 1)
                        ? effects.effects[position - 1].name : "empty"
                    Text("\(position) — \(name)").tag(HotkeyAction.effectIndex(position))
                }
            }
            if !store.scenes.isEmpty {
                Section("Pinned scene") {
                    ForEach(store.scenes) { Text($0.name).tag(HotkeyAction.scene($0.id)) }
                }
            }
            if !effects.effects.isEmpty {
                Section("Pinned effect") {
                    ForEach(effects.effects) { Text($0.name).tag(HotkeyAction.effect($0.id)) }
                }
            }
        }
        .labelsHidden()
    }
}

// MARK: - Drag and drop

/// Actions travel between the reference lists and the pad as a short string, because
/// `Transferable` on an enum with associated values needs a custom UTType and this does not
/// warrant one. Anything unrecognised is simply refused.
extension HotkeyAction {
    var dragPayload: String {
        switch self {
        case .none: "none"
        case .stopAll: "stopAll"
        case .volumeUp: "volumeUp"
        case .volumeDown: "volumeDown"
        case .nextScene: "nextScene"
        case .previousScene: "previousScene"
        case .newScene: "newScene"
        case .toggleMute: "toggleMute"
        case .togglePlayPause: "togglePlayPause"
        case .sceneIndex(let n): "sceneIndex:\(n)"
        case .effectIndex(let n): "effectIndex:\(n)"
        case .scene(let id): "scene:\(id.uuidString)"
        case .effect(let id): "effect:\(id.uuidString)"
        }
    }

    static func fromDragPayload(_ raw: String) -> HotkeyAction? {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "none": return HotkeyAction.none
        case "stopAll": return .stopAll
        case "volumeUp": return .volumeUp
        case "volumeDown": return .volumeDown
        case "nextScene": return .nextScene
        case "previousScene": return .previousScene
        case "newScene": return .newScene
        case "toggleMute": return .toggleMute
        case "togglePlayPause": return .togglePlayPause
        case "sceneIndex": return Int(parts.last ?? "").map { .sceneIndex($0) }
        case "effectIndex": return Int(parts.last ?? "").map { .effectIndex($0) }
        case "scene": return UUID(uuidString: parts.last ?? "").map { .scene($0) }
        case "effect": return UUID(uuidString: parts.last ?? "").map { .effect($0) }
        default: return nil
        }
    }
}

/// Makes a key, knob face or rotation label accept a dropped action. A nil slot is inert, so
/// the keys DMC cannot hear reject drops rather than pretending to take them.
struct SlotDropTarget: ViewModifier {
    let slot: Int?
    @Binding var hovered: Int?
    let assign: (String, Int) -> Bool

    func body(content: Content) -> some View {
        if let slot {
            content.dropDestination(for: String.self) { items, _ in
                hovered = nil
                guard let payload = items.first else { return false }
                return assign(payload, slot)
            } isTargeted: { targeted in
                if targeted { hovered = slot } else if hovered == slot { hovered = nil }
            }
        } else {
            content
        }
    }
}

/// A draggable chip for the transport actions, so everything bindable can be dragged and not
/// just the named scenes and effects.
struct ActionChip: View {
    let action: HotkeyAction
    let label: String
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.system(size: 10))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .draggable(action.dragPayload) {
                Label(label, systemImage: systemImage)
                    .padding(6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
    }
}

enum PadMapperWindow {
    static let id = "macropad"
}
