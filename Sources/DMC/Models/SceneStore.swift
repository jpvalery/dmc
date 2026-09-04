import Combine
import Foundation

@MainActor
final class SceneStore: ObservableObject {
    @Published private(set) var scenes: [SoundScene] = []
    /// Files present in the vault that macOS cannot decode, surfaced rather than skipped.
    @Published private(set) var unplayable: [String] = []

    init() {
        Vault.bootstrap()
        reload()
    }

    func reload() {
        scenes = SceneLibrary.load()
        unplayable = SceneLibrary.unplayableFiles()
    }

    func upsert(_ scene: SoundScene) {
        if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
            scenes[index] = scene
        } else {
            scenes.append(scene)
        }
        persist()
    }

    func delete(_ scene: SoundScene) {
        scenes.removeAll { $0.id == scene.id }
        persist()
    }

    func duplicate(_ scene: SoundScene) {
        var copy = scene
        copy.id = UUID()
        copy.name = "\(scene.name) copy"
        copy.layers = scene.layers.map { layer in
            var l = layer
            l.id = UUID()
            return l
        }
        scenes.append(copy)
        persist()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        scenes.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persist()
    }

    /// Bring in any audio subfolder that isn't already a scene.
    ///
    /// Saving a scene creates `scenes.json`, which switches off the folder-per-scene fallback —
    /// this puts that convenience back within reach on demand.
    func importFolders() {
        let existing = Set(scenes.map(\.name))
        let derived = SceneLibrary.derivedFromFolders().filter { !existing.contains($0.name) }
        guard !derived.isEmpty else { return }
        scenes.append(contentsOf: derived)
        persist()
    }

    private func persist() {
        SceneLibrary.save(scenes)
    }
}
