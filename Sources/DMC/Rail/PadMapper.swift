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

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSlot: Int?
    /// The slot a drag is currently hovering, for highlight.
    @State private var dropSlot: Int?
    @State private var showAllSlots = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    encoderRow
                    gridView
                    assignment
                    Divider()
                    reference
                    allSlotsDisclosure
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 660)
    }

    // MARK: - Pieces

    private var headerBar: some View {
        HStack {
            Text("Macropad & hotkeys").font(.headline)
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var encoderRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENCODERS").font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(PadSpec.encoders) { encoder in
                    knob(encoder)
                }
            }
        }
    }

    private func knob(_ encoder: PadSpec.Encoder) -> some View {
        VStack(spacing: 5) {
            Text(encoder.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                rotation(slot: encoder.ccw, fixed: encoder.fixed?.ccw,
                         glyph: "arrow.counterclockwise", alignment: .trailing)
                press(slot: encoder.press, fixed: encoder.fixed?.press)
                rotation(slot: encoder.cw, fixed: encoder.fixed?.cw,
                         glyph: "arrow.clockwise", alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// One side of the knob: which way you turn it, and what that does.
    private func rotation(slot: Int?, fixed: String?, glyph: String,
                          alignment: Alignment) -> some View {
        let isSelected = slot != nil && slot == selectedSlot
        return VStack(spacing: 2) {
            Image(systemName: glyph)
                .font(.system(size: 9))
                .foregroundStyle(slot == nil ? .tertiary : .secondary)
            Text(slot.map { describe(hotkeys.binding(for: HotkeySlot.all[$0])) } ?? (fixed ?? "—"))
                .font(.system(size: 9))
                .foregroundStyle(slot == nil ? .tertiary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: alignment)
        .padding(.vertical, 3)
        .padding(.horizontal, 3)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { if let slot { selectedSlot = slot } }
        .modifier(SlotDropTarget(slot: slot, hovered: $dropSlot, assign: assign))
    }

    /// The knob itself — pressing it is a binding too, so the circle is a drop target.
    private func press(slot: Int?, fixed: String?) -> some View {
        let isSelected = slot != nil && slot == selectedSlot
        let isHovered = slot != nil && slot == dropSlot
        return VStack(spacing: 1) {
            Circle()
                .strokeBorder(isSelected || isHovered ? Color.accentColor
                                                     : Color(nsColor: .separatorColor),
                              lineWidth: isSelected || isHovered ? 2 : 1)
                .background(Circle().fill(slot == nil ? Color(nsColor: .controlBackgroundColor)
                                                      : Color(nsColor: .controlBackgroundColor)))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: pressGlyph(slot: slot, fixed: fixed))
                        .font(.system(size: 12))
                        .foregroundStyle(slot == nil ? .tertiary : .primary)
                }
            Text(slot.map { describe(hotkeys.binding(for: HotkeySlot.all[$0])) } ?? (fixed ?? "—"))
                .font(.system(size: 8))
                .foregroundStyle(slot == nil ? .tertiary : .secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { if let slot { selectedSlot = slot } }
        .modifier(SlotDropTarget(slot: slot, hovered: $dropSlot, assign: assign))
        .help(slot == nil ? (fixed ?? "") : "Click to bind, or drop a scene or effect here")
    }

    private func pressGlyph(slot: Int?, fixed: String?) -> String {
        guard let slot else { return "hand.tap" }
        switch hotkeys.binding(for: HotkeySlot.all[slot]) {
        case .togglePlayPause: return "playpause.fill"
        case .stopAll: return "stop.fill"
        case .toggleMute: return "speaker.slash.fill"
        case .none: return "circle.dashed"
        default: return "hand.tap.fill"
        }
    }

    private var gridView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KEYS").font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(Array(PadSpec.grid.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row) { key in keyCell(key) }
                    }
                }
            }
        }
    }

    private func keyCell(_ key: PadSpec.Key) -> some View {
        let bound = key.slot.map { hotkeys.binding(for: HotkeySlot.all[$0]) } ?? .none
        let isSelected = key.slot != nil && key.slot == selectedSlot
        let isHovered = key.slot != nil && key.slot == dropSlot
        let unreachable = key.slot == nil

        return Button {
            if let slot = key.slot { selectedSlot = slot }
        } label: {
            VStack(spacing: 3) {
                Text(key.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(unreachable ? .tertiary : .secondary)
                Text(unreachable ? "not a hotkey" : describe(bound))
                    .font(.system(size: 10))
                    .foregroundStyle(unreachable ? .tertiary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .background(
                isHovered ? Color.accentColor.opacity(0.4)
                          : (isSelected ? Color.accentColor.opacity(0.28)
                             : (unreachable ? Color(nsColor: .windowBackgroundColor)
                                            : Color(nsColor: .controlBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered || isSelected ? Color.accentColor
                                                    : Color(nsColor: .separatorColor),
                            lineWidth: isHovered ? 2 : (isSelected ? 1.5 : 0.5))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(unreachable)
        .modifier(SlotDropTarget(slot: key.slot, hovered: $dropSlot, assign: assign))
        .help(unreachable
              ? "\(key.via) — remap it in VIA to F20 to reach DMC"
              : "\(key.via) — click to bind, or drop a scene or effect here")
    }

    @ViewBuilder
    private var assignment: some View {
        if let slot = selectedSlot {
            let padSlot = HotkeySlot.all[slot]
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(padSlot.label)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
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
            .padding(10)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text("Pick a key or encoder action above to bind it.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
    }

    /// What "Scene 3" and "Effect 2" refer to right now — and the drag source for binding them.
    private var reference: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DRAG ONTO A KEY OR KNOB")
                .font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ActionChip(action: .togglePlayPause, label: "Pause", systemImage: "playpause.fill")
                    ActionChip(action: .stopAll, label: "Stop all", systemImage: "stop.fill")
                    ActionChip(action: .toggleMute, label: "Mute", systemImage: "speaker.slash.fill")
                    ActionChip(action: .volumeUp, label: "Vol +", systemImage: "speaker.wave.2.fill")
                    ActionChip(action: .volumeDown, label: "Vol −", systemImage: "speaker.fill")
                    ActionChip(action: .nextScene, label: "Next", systemImage: "forward.fill")
                    ActionChip(action: .previousScene, label: "Prev", systemImage: "backward.fill")
                    ActionChip(action: .newScene, label: "New scene", systemImage: "plus")
                }
                .padding(.vertical, 1)
            }

            HStack(alignment: .top, spacing: 16) {
                column(title: "SCENES", systemImage: "waveform",
                       rows: store.scenes.enumerated().map {
                           ($0.offset + 1, $0.element.name, $0.element.symbol,
                            HotkeyAction.scene($0.element.id))
                       },
                       empty: "No scenes yet")
                column(title: "EFFECTS", systemImage: "bolt.fill",
                       rows: effects.effects.enumerated().map {
                           ($0.offset + 1, $0.element.name, $0.element.symbol,
                            HotkeyAction.effect($0.element.id))
                       },
                       empty: "No effects yet")
            }
        }
    }

    private func column(title: String, systemImage: String,
                        rows: [(Int, String, String, HotkeyAction)],
                        empty: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(empty).font(.caption2).foregroundStyle(.tertiary)
            } else {
                // Scrolls once there are more than fit: truncating the list silently hid
                // scenes 10 and up, which made the mapper look like it had lost them.
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(rows, id: \.0) { index, name, symbol, action in
                    HStack(spacing: 5) {
                        Text("\(index)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12, alignment: .trailing)
                        Image(systemName: symbol).font(.system(size: 9))
                            .foregroundStyle(.secondary).frame(width: 12)
                        Text(name).font(.caption).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                    // Dropping a named thing pins that thing. By-position bindings stay
                    // available in the picker, where the distinction can be spelled out.
                    .draggable(action.dragPayload) {
                        Label(name, systemImage: symbol)
                            .padding(6)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allSlotsDisclosure: some View {
        DisclosureGroup(isExpanded: $showAllSlots) {
            VStack(spacing: 2) {
                ForEach(HotkeySlot.all.filter { slot in
                    // Everything the pad cannot send, for other keyboards.
                    !PadSpec.grid.flatMap { $0 }.compactMap(\.slot).contains(slot.index)
                        && ![4, 5, 6].contains(slot.index)
                }) { slot in
                    HStack(spacing: 8) {
                        Text(slot.label)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 42, alignment: .leading)
                        Text(slot.viaCode)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 118, alignment: .leading)
                        ActionPicker(selection: Binding(
                            get: { hotkeys.binding(for: slot) },
                            set: { hotkeys.setBinding($0, for: slot) }
                        ), store: store, effects: effects)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Other slots (not on this pad)").font(.caption)
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

    // MARK: - Helpers

    /// Applies a dropped payload. Returns false for anything unrecognised so the drop animates
    /// back rather than silently doing nothing.
    private func assign(_ payload: String, to slot: Int) -> Bool {
        guard let action = HotkeyAction.fromDragPayload(payload) else { return false }
        hotkeys.setBinding(action, for: HotkeySlot.all[slot])
        selectedSlot = slot
        return true
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
        case .scene(let id):
            store.scenes.first { $0.id == id }?.name ?? "(deleted scene)"
        case .effect(let id):
            effects.effects.first { $0.id == id }?.name ?? "(deleted effect)"
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

/// The action menu, shared by the pad cells and the overflow list.
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
