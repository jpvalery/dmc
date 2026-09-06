import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

enum HotkeyAction: Codable, Hashable {
    case none
    /// Pinned to one scene, wherever it sits in the rail.
    case scene(UUID)
    /// Whatever is at this 1-based position in the rail. Survives renaming, deleting and
    /// recreating a scene, and follows the rail when scenes are dragged into a new order —
    /// which is what muscle memory actually wants from a pad.
    case sceneIndex(Int)
    case stopAll
    case volumeUp
    case volumeDown
    /// Step through the rail. Made for a rotary encoder, where turning is cheap and precise.
    case nextScene
    case previousScene
    /// Opens the scene editor on a blank scene — building a new ambience without leaving the pad.
    case newScene
    /// Silence the ambience without stopping it.
    case toggleMute
    /// Pause the mix in place and resume it mid-loop.
    case togglePlayPause
    /// Fire the effect at this 1-based position in the effects list.
    case effectIndex(Int)
    /// Fire one specific effect, wherever it sits.
    case effect(UUID)
}

/// A macropad key DMC listens for.
///
/// F13–F20 are the highest function keys with defined macOS virtual keycodes (F21 and up have
/// none), so reach is extended with modifiers instead: those eight keys bare, then with Shift,
/// Control and Option. That is 32 slots — enough for 15 keys plus three encoders (each
/// contributing clockwise, counter-clockwise and press). Modified F13–F20 collide with nothing
/// on macOS.
struct HotkeySlot: Identifiable, Hashable {
    let index: Int
    let keyCode: Int
    let carbonModifiers: UInt32

    var id: Int { index }

    private static let codes = [kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
    private static let banks: [(symbol: String, via: (String) -> String, carbon: UInt32)] = [
        ("",  { $0 },              0),
        ("⇧", { "LSFT(\($0))" },   UInt32(shiftKey)),
        ("⌃", { "LCTL(\($0))" },   UInt32(controlKey)),
        ("⌥", { "LALT(\($0))" },   UInt32(optionKey)),
    ]

    var bank: Int { index / 8 }
    var keyName: String { "F\(13 + index % 8)" }
    var label: String { Self.banks[bank].symbol + keyName }
    /// The code to type into VIA's "Any" key field.
    var viaCode: String { Self.banks[bank].via("KC_\(keyName)") }

    static let all: [HotkeySlot] = (0..<32).map { i in
        HotkeySlot(index: i, keyCode: codes[i % 8], carbonModifiers: banks[i / 8].carbon)
    }
}

/// System-wide hotkeys via the Carbon hotkey API.
///
/// `RegisterEventHotKey` is used rather than a `CGEventTap` because it needs no Accessibility
/// permission, and because it works while D&D Beyond has focus — which is the whole point of a
/// macropad on the table.
@MainActor
final class HotkeyManager: ObservableObject {
    @Published var bindings: [Int: HotkeyAction] = [:] {
        didSet { persist(); register() }
    }

    /// Dispatched on the main actor when a bound key fires.
    var onAction: ((HotkeyAction) -> Void)?

    private static let signature = OSType(0x444D4321)  // 'DMC!'
    private static weak var current: HotkeyManager?

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init() {
        Vault.bootstrap()
        Self.current = self
        bindings = Self.saved() ?? Self.starterLayout
        register()
    }

    /// Bindings name scene ids, so they belong to the campaign those scenes live in.
    private static func saved() -> [Int: HotkeyAction]? {
        guard let data = try? Data(contentsOf: Vault.hotkeysFile),
              let decoded = try? JSONDecoder().decode([Int: HotkeyAction].self, from: data),
              !decoded.isEmpty
        else { return nil }
        return decoded
    }

    /// Matches the Winry315 pad on this desk: 12 keys in a 4x3 grid sending F13-F16 bare
    /// (slots 0-3), with Shift (slots 8-11) and with Control (slots 16-19). The Control row is
    /// transport; the two above it are the first eight rail positions.
    /// The pad numbers its macros column-major (M0/M1/M2 are column one, top to bottom), so
    /// M0-M8 are the first three columns and become rail positions 1-9 reading *down* each
    /// column. The fourth column (M9/M10/M11) is scene navigation.
    ///
    ///     M0 -> F13        M1 -> LSFT(F13)   M2 -> LCTL(F13)
    ///     M3 -> F14        M4 -> LSFT(F14)   M5 -> LCTL(F14)   ... etc
    static let padLayout: [Int: HotkeyAction] = [
        // Read down each column: the pad numbers its macros column-major, so M0/M1/M2 are the
        // first column top to bottom, M3/M4/M5 the second, and so on.
        //
        //   col 1        col 2      col 3      col 4
        //   previous     scene 1    scene 4    effect 2
        //   next         scene 2    scene 5    effect 3
        //   effect 1     scene 3    scene 6    effect 4
        0: .previousScene,  1: .sceneIndex(1),  2: .sceneIndex(4),  3: .effectIndex(2),
        8: .nextScene,      9: .sceneIndex(2), 10: .sceneIndex(5), 11: .effectIndex(3),
       16: .effectIndex(1), 17: .sceneIndex(3), 18: .sceneIndex(6), 19: .effectIndex(4),

        // The left knob drives DMC's own master volume rather than the system's: macOS routes
        // system volume to AirPods over AVRCP absolute volume, which coalesces rapid encoder
        // taps into jumps instead of steps.
        //
        // Bare F17-F19 specifically. F14/F15 are brightness on Apple keyboards and macOS claims
        // them whatever modifier is added — LALT(F14) opened Displays settings *as well as*
        // firing here. F17-F20 carry no default binding, so no modifier is needed at all.
        4: .volumeUp, 5: .volumeDown, 6: .togglePlayPause,
    ]

    private static let starterLayout: [Int: HotkeyAction] = padLayout

    func reloadForCampaign() {
        bindings = Self.saved() ?? Self.starterLayout
    }

    // No deinit: `current` is a weak reference that clears itself, and this manager lives for
    // the whole app session, so there is nothing to tear down.

    func binding(for slot: HotkeySlot) -> HotkeyAction {
        bindings[slot.index] ?? .none
    }

    func setBinding(_ action: HotkeyAction, for slot: HotkeySlot) {
        var next = bindings
        if action == .none { next.removeValue(forKey: slot.index) } else { next[slot.index] = action }
        bindings = next
    }

    func register() {
        unregisterAll()
        installHandler()

        for slot in HotkeySlot.all {
            let action = bindings[slot.index] ?? .none
            guard action != .none else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(slot.index))
            let status = RegisterEventHotKey(UInt32(slot.keyCode), slot.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
        }
    }

    func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotkeyManager.current?.fire(index) }
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func fire(_ index: Int) {
        guard let action = bindings[index], action != .none else { return }
        onAction?(action)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        try? data.write(to: Vault.hotkeysFile, options: .atomic)
    }
}
