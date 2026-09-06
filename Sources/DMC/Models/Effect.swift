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
    /// Alternate takes chosen at random per firing, so three knocks aren't three identical ones.
    var variants: [String] = []

    var url: URL { Vault.audio.appending(path: file) }
    var isMissing: Bool { !FileManager.default.fileExists(atPath: url.path) }

    /// One of `file` or `variants`, picked fresh each time it fires.
    var randomURL: URL {
        let all = ([file] + variants).filter { !$0.isEmpty }
        return Vault.audio.appending(path: all.randomElement() ?? file)
    }

    /// Decoded by hand for the same reason as `AudioLayer`: Swift's synthesized `Codable`
    /// ignores property defaults, so a field added later would orphan every effect already
    /// written to disk.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "bell"
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
        gain = try c.decodeIfPresent(Double.self, forKey: .gain) ?? 0.9
        variants = try c.decodeIfPresent([String].self, forKey: .variants) ?? []
    }

    init(name: String, symbol: String = "bell", file: String, gain: Double = 0.9,
         variants: [String] = []) {
        self.name = name
        self.symbol = symbol
        self.file = file
        self.gain = gain
        self.variants = variants
    }
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
