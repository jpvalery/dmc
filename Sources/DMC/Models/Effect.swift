import Combine
import Foundation

/// A one-shot overlay: a door slam, a thunderclap, a scream.
///
/// Unlike a scene it does not loop, does not fade, and does not replace what is already playing —
/// several can overlap each other and the scene bed underneath.
struct SoundEffect: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "bell"
    /// Relative to `Vault.audio`, the same convention as `AudioLayer.file`.
    var file: String
    var gain: Double = 0.9

    var url: URL { Vault.audio.appending(path: file) }
    var isMissing: Bool { !FileManager.default.fileExists(atPath: url.path) }
}

enum EffectLibrary {
    static func load() -> [SoundEffect] {
        guard let data = try? Data(contentsOf: Vault.effectsFile),
              let effects = try? JSONDecoder().decode([SoundEffect].self, from: data)
        else { return [] }
        return effects
    }

    static func save(_ effects: [SoundEffect]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(effects).write(to: Vault.effectsFile, options: .atomic)
    }
}

@MainActor
final class EffectStore: ObservableObject {
    @Published private(set) var effects: [SoundEffect] = []

    init() {
        Vault.bootstrap()
        reload()
    }

    func reload() { effects = EffectLibrary.load() }

    func upsert(_ effect: SoundEffect) {
        if let i = effects.firstIndex(where: { $0.id == effect.id }) {
            effects[i] = effect
        } else {
            effects.append(effect)
        }
        persist()
    }

    func delete(_ effect: SoundEffect) {
        effects.removeAll { $0.id == effect.id }
        persist()
    }

    /// Same identity-based reordering as scenes, so a drag resolves against the current order.
    func move(_ id: UUID, before targetID: UUID?) {
        guard id != targetID, let from = effects.firstIndex(where: { $0.id == id }) else { return }
        let moving = effects.remove(at: from)
        if let targetID, let to = effects.firstIndex(where: { $0.id == targetID }) {
            effects.insert(moving, at: to)
        } else {
            effects.append(moving)
        }
        persist()
    }

    func contains(_ id: UUID) -> Bool { effects.contains { $0.id == id } }

    private func persist() { EffectLibrary.save(effects) }
}
