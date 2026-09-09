import Combine
import Foundation

/// Anything that ships as a recipe: it names the audio it needs and where to fetch it, so the
/// same download-then-add flow serves both scenes and effects.
protocol AudioTemplate: Identifiable, Hashable {
    var name: String { get }
    var symbol: String { get }
    var tags: [String] { get }
    /// Every vault-relative path this template needs, variants included.
    var files: [String] { get }
    func downloadURL(for path: String) -> URL?
}

extension AudioTemplate {
    var missingFiles: [String] {
        files.filter { !FileManager.default.fileExists(atPath: Vault.audio.appending(path: $0).path) }
    }
}

/// A ready-made scene that can be added to any campaign, and re-added after deletion.
///
/// Templates ship inside the app rather than living in a campaign, so deleting the scenes they
/// produced never loses the recipe. Each layer carries a download URL, so a template can be
/// used on a vault that has none of the audio yet.
struct SceneTemplate: Codable, AudioTemplate {
    struct Layer: Codable, Hashable {
        var file: String
        var download: String?
        var gain: Double = 0.8
        var loops: Bool = true
        var randomStart: Bool = true
        var sporadic: Bool = false
        var minGap: Double = 8
        var maxGap: Double = 20
        var variants: [String] = []
        var variantDownloads: [String] = []
    }

    var id: String { name }
    var name: String
    var symbol: String
    var tags: [String] = []
    var credit: String = ""
    var layers: [Layer]

    var loopCount: Int { layers.filter { !$0.sporadic }.count }
    var sporadicCount: Int { layers.filter(\.sporadic).count }

    var files: [String] { layers.flatMap { [$0.file] + $0.variants } }

    /// Fresh ids each time, so adding a template twice gives two independent scenes.
    func makeScene() -> SoundScene {
        SoundScene(name: name, symbol: symbol, layers: layers.map { l in
            AudioLayer(file: l.file, gain: l.gain, loops: l.loops, randomStart: l.randomStart,
                       sporadic: l.sporadic, minGap: l.minGap, maxGap: l.maxGap,
                       variants: l.variants)
        })
    }

    /// Remote URL for a vault-relative path, for fetching what is missing.
    func downloadURL(for path: String) -> URL? {
        for layer in layers {
            if layer.file == path, let d = layer.download { return URL(string: d) }
            if let i = layer.variants.firstIndex(of: path), i < layer.variantDownloads.count {
                return URL(string: layer.variantDownloads[i])
            }
        }
        return nil
    }
}

/// A ready-made effect. Same contract as a scene template, one file plus optional extra takes.
struct EffectTemplate: Codable, AudioTemplate {
    var id: String { name }
    var name: String
    var symbol: String
    var tags: [String] = []
    var gain: Double = 0.85
    var credit: String = ""
    var file: String
    var download: String?
    var variants: [String] = []
    var variantDownloads: [String] = []

    var files: [String] { [file] + variants }
    var takeCount: Int { files.count }

    func makeEffect() -> SoundEffect {
        SoundEffect(name: name, symbol: symbol, file: file, gain: gain, variants: variants)
    }

    func downloadURL(for path: String) -> URL? {
        if path == file, let download { return URL(string: download) }
        if let i = variants.firstIndex(of: path), i < variantDownloads.count {
            return URL(string: variantDownloads[i])
        }
        return nil
    }
}

@MainActor
final class TemplateLibrary: ObservableObject {
    @Published private(set) var templates: [SceneTemplate] = []
    @Published private(set) var effectTemplates: [EffectTemplate] = []
    @Published private(set) var note: String = ""

    private struct Document: Codable {
        var note: String?
        var templates: [SceneTemplate]
    }

    private struct EffectDocument: Codable {
        var note: String?
        var templates: [EffectTemplate]
    }

    init() {
        load()
        loadEffects()
    }

    private func loadEffects() {
        let candidates = [
            Vault.root.appending(path: "effect-templates.json"),
            Bundle.main.url(forResource: "effect-templates", withExtension: "json"),
        ].compactMap { $0 }
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let doc = try? JSONDecoder().decode(EffectDocument.self, from: data),
                  !doc.templates.isEmpty
            else { continue }
            effectTemplates = doc.templates.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return
        }
    }

    private func load() {
        // A copy in the vault wins, so templates can be edited without rebuilding the app.
        let candidates = [
            Vault.root.appending(path: "scene-templates.json"),
            Bundle.main.url(forResource: "scene-templates", withExtension: "json"),
        ].compactMap { $0 }

        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let doc = try? JSONDecoder().decode(Document.self, from: data),
                  !doc.templates.isEmpty
            else { continue }
            templates = doc.templates.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            note = doc.note ?? ""
            return
        }
    }
}
