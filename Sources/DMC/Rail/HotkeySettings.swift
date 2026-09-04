import AppKit
import SwiftUI

struct HotkeySettings: View {
    @ObservedObject var hotkeys: HotkeyManager
    @ObservedObject var store: SceneStore

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private static let bankNames = ["Plain", "Shift", "Control", "Option"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Macropad & hotkeys").font(.headline)
                Text("These fire system-wide, so they work while D&D Beyond has focus. "
                     + "In VIA, set each key to **Any** and type the code shown here. "
                     + "For a rotary knob, VIA gives you separate clockwise and "
                     + "counter-clockwise slots plus the press.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)

            Divider()

            List {
                ForEach(0..<4, id: \.self) { bank in
                    Section(Self.bankNames[bank]) {
                        ForEach(HotkeySlot.all.filter { $0.bank == bank }) { slot in
                            row(slot)
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 8) {
                Button("Suggested layout") { applySuggestedLayout() }
                    .help("15 keys to your first 15 scenes, three encoders on the Control bank")
                Button("Clear all") {
                    for slot in HotkeySlot.all { hotkeys.setBinding(.none, for: slot) }
                }
                Button(copied ? "Copied" : "Copy VIA sheet") { copyCheatSheet() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 620)
    }

    private func row(_ slot: HotkeySlot) -> some View {
        HStack(spacing: 8) {
            Text(slot.label)
                .font(.system(.body, design: .monospaced))
                .frame(width: 46, alignment: .leading)

            Text(slot.viaCode)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(width: 128, alignment: .leading)

            Picker("", selection: Binding(
                get: { hotkeys.binding(for: slot) },
                set: { hotkeys.setBinding($0, for: slot) }
            )) {
                Text("— nothing —").tag(HotkeyAction.none)
                Divider()
                Text("Stop all audio").tag(HotkeyAction.stopAll)
                Text("Volume up").tag(HotkeyAction.volumeUp)
                Text("Volume down").tag(HotkeyAction.volumeDown)
                Text("Next scene").tag(HotkeyAction.nextScene)
                Text("Previous scene").tag(HotkeyAction.previousScene)
                if !store.scenes.isEmpty {
                    Divider()
                    ForEach(store.scenes) { scene in
                        Text("Scene: \(scene.name)").tag(HotkeyAction.scene(scene.id))
                    }
                }
            }
            .labelsHidden()
        }
    }

    /// Fifteen pad keys onto the bare and Shift banks, then the three encoders onto Control.
    private func applySuggestedLayout() {
        for slot in HotkeySlot.all { hotkeys.setBinding(.none, for: slot) }

        for (index, scene) in store.scenes.prefix(15).enumerated() {
            hotkeys.setBinding(.scene(scene.id), for: HotkeySlot.all[index])
        }
        // Encoder 1 on ⌃F13–⌃F15, encoder 2 on ⌃F16–⌃F18. Encoder 3 (⌃F19, ⌃F20, ⌥F13) is
        // left free — there is no third action worth inventing yet.
        let encoders: [(Int, HotkeyAction)] = [
            (16, .volumeUp), (17, .volumeDown), (18, .stopAll),
            (19, .nextScene), (20, .previousScene),
        ]
        for (index, action) in encoders {
            hotkeys.setBinding(action, for: HotkeySlot.all[index])
        }
    }

    private func copyCheatSheet() {
        var lines = ["DMC macropad mapping", "", "VIA code            Key    Action"]
        for slot in HotkeySlot.all {
            let action = hotkeys.binding(for: slot)
            guard action != .none else { continue }
            let name = describe(action)
            lines.append(slot.viaCode.padding(toLength: 20, withPad: " ", startingAt: 0)
                         + slot.label.padding(toLength: 7, withPad: " ", startingAt: 0)
                         + name)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }

    private func describe(_ action: HotkeyAction) -> String {
        switch action {
        case .none: "—"
        case .stopAll: "Stop all audio"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .nextScene: "Next scene"
        case .previousScene: "Previous scene"
        case .scene(let id): store.scenes.first { $0.id == id }.map { "Scene: \($0.name)" } ?? "Scene: (deleted)"
        }
    }
}
