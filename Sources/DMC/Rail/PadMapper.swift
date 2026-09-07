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

    /// The left knob is the only encoder DMC hears; the other two act on the host or the board.
    static let encoders: [(name: String, slots: [Int?], detail: String)] = [
        ("Left",   [5, 4, 6], "F18 · F17 · F19"),
        ("Centre", [nil, nil, nil], "mousewheel · middle click"),
        ("Right",  [nil, nil, nil], "RGB brightness · mode"),
    ]
}

struct PadMapper: View {
    @ObservedObject var hotkeys: HotkeyManager
    @ObservedObject var store: SceneStore
    @ObservedObject var effects: EffectStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSlot: Int?
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
            HStack(spacing: 8) {
                ForEach(PadSpec.encoders, id: \.name) { encoder in
                    VStack(spacing: 4) {
                        Text(encoder.name).font(.caption.weight(.medium))
                        if encoder.slots.contains(where: { $0 != nil }) {
                            ForEach(Array(zip(["⟲", "⟳", "press"], encoder.slots)), id: \.0) { symbol, slot in
                                if let slot {
                                    Button { selectedSlot = slot } label: {
                                        HStack(spacing: 3) {
                                            Text(symbol).font(.system(size: 9))
                                            Text(describe(hotkeys.binding(for: HotkeySlot.all[slot])))
                                                .font(.system(size: 9)).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 2)
                                        .background(selectedSlot == slot ? Color.accentColor.opacity(0.25)
                                                                         : Color(nsColor: .controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            Text(encoder.detail)
                                .font(.system(size: 9)).foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
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
                isSelected ? Color.accentColor.opacity(0.28)
                           : (unreachable ? Color(nsColor: .windowBackgroundColor)
                                          : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(unreachable)
        .help(unreachable ? "\(key.via) — remap it in VIA to F20 to reach DMC" : key.via)
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

    /// What "Scene 3" and "Effect 2" actually refer to right now.
    private var reference: some View {
        HStack(alignment: .top, spacing: 16) {
            column(title: "SCENES", systemImage: "waveform",
                   rows: store.scenes.prefix(9).enumerated().map { ($0.offset + 1, $0.element.name) },
                   empty: "No scenes yet")
            column(title: "EFFECTS", systemImage: "bolt.fill",
                   rows: effects.effects.prefix(8).enumerated().map { ($0.offset + 1, $0.element.name) },
                   empty: "No effects yet")
        }
    }

    private func column(title: String, systemImage: String,
                        rows: [(Int, String)], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(empty).font(.caption2).foregroundStyle(.tertiary)
            } else {
                ForEach(rows, id: \.0) { index, name in
                    HStack(spacing: 5) {
                        Text("\(index)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12, alignment: .trailing)
                        Text(name).font(.caption).lineLimit(1)
                    }
                }
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
                ForEach(1...16, id: \.self) { position in
                    let name = store.scenes.indices.contains(position - 1)
                        ? store.scenes[position - 1].name : "empty"
                    Text("\(position) — \(name)").tag(HotkeyAction.sceneIndex(position))
                }
            }
            Section("Effect by position") {
                ForEach(1...8, id: \.self) { position in
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
