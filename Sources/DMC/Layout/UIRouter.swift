import Combine
import Foundation

/// Sheet routing shared between the menu bar and the views.
///
/// `.commands` is declared on the `App`, outside the view tree, so it cannot reach view-local
/// `@State`. One small observable keeps a single source of truth for both.
@MainActor
final class UIRouter: ObservableObject {
    struct EditorTarget: Identifiable {
        let id = UUID()
        var scene: SoundScene
        var isNew: Bool
    }

    struct EffectTarget: Identifiable {
        let id = UUID()
        var effect: SoundEffect
        var isNew: Bool
    }

    @Published var editing: EditorTarget?
    @Published var editingEffect: EffectTarget?
    @Published var showTabletop = false
    @Published var showTemplates = false
    @Published var showPadImport = false
    @Published var showHotkeys = false
    @Published var showNewCampaign = false
    @Published var renaming: Campaign?
    @Published var deleting: Campaign?

    func newScene() {
        editing = EditorTarget(scene: SoundScene(name: "New scene", symbol: "waveform"), isNew: true)
    }

    func edit(_ scene: SoundScene) {
        editing = EditorTarget(scene: scene, isNew: false)
    }

    func newEffect() {
        editingEffect = EffectTarget(effect: SoundEffect(name: "", symbol: "bell", file: ""),
                                     isNew: true)
    }

    func edit(_ effect: SoundEffect) {
        editingEffect = EffectTarget(effect: effect, isNew: false)
    }
}
