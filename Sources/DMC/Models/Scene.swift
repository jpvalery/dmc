import Foundation

/// One sound inside a scene. `file` is stored relative to `Vault.audio` so `scenes.json`
/// stays portable if the vault moves.
struct AudioLayer: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var file: String
    var gain: Double = 0.8
    var loops: Bool = true
    /// Begin at a random offset. Without this, several equal-length loops in one scene
    /// phase-lock and the mix develops an audible repeating pattern.
    var randomStart: Bool = true
    var pan: Double = 0
    /// Fires at random intervals instead of looping: a distant owl, a dripping pipe, a creak.
    /// This is what stops a bed sounding like a loop — the irregularity is the point.
    var sporadic: Bool = false
    var minGap: Double = 8
    var maxGap: Double = 20
    /// Alternate files chosen at random alongside `file`, so repeats don't sound identical.
    var variants: [String] = []

    /// Set when the layer came from an imported SoundPad slot and has no file bound yet.
    /// Keeping the original slot id is what lets the imported mix be reassembled by hand.
    var padID: String?

    /// An imported slot with nothing chosen yet. Unbound layers are skipped at playback and
    /// flagged in the editor rather than failing silently.
    var isBound: Bool { !file.isEmpty }
    var url: URL { Vault.audio.appending(path: file) }

    /// Decoded by hand because Swift's synthesized `Codable` ignores property defaults: a key
    /// absent from an older `scenes.json` throws instead of falling back, which would break
    /// every layer written before a new field was added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
        gain = try c.decodeIfPresent(Double.self, forKey: .gain) ?? 0.8
        loops = try c.decodeIfPresent(Bool.self, forKey: .loops) ?? true
        randomStart = try c.decodeIfPresent(Bool.self, forKey: .randomStart) ?? true
        pan = try c.decodeIfPresent(Double.self, forKey: .pan) ?? 0
        sporadic = try c.decodeIfPresent(Bool.self, forKey: .sporadic) ?? false
        minGap = try c.decodeIfPresent(Double.self, forKey: .minGap) ?? 8
        maxGap = try c.decodeIfPresent(Double.self, forKey: .maxGap) ?? 20
        variants = try c.decodeIfPresent([String].self, forKey: .variants) ?? []
        padID = try c.decodeIfPresent(String.self, forKey: .padID)
    }

    init(file: String, gain: Double = 0.8, loops: Bool = true, randomStart: Bool = true,
         pan: Double = 0, sporadic: Bool = false, minGap: Double = 8, maxGap: Double = 20,
         variants: [String] = [], padID: String? = nil) {
        self.file = file
        self.gain = gain
        self.loops = loops
        self.randomStart = randomStart
        self.pan = pan
        self.sporadic = sporadic
        self.minGap = minGap
        self.maxGap = maxGap
        self.variants = variants
        self.padID = padID
    }

    /// One of `file` or `variants`, picked fresh for each firing.
    var randomVariantURL: URL {
        let all = [file] + variants.filter { !$0.isEmpty }
        return Vault.audio.appending(path: all.randomElement() ?? file)
    }
}

struct SoundScene: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "waveform"
    var layers: [AudioLayer] = []
    var fadeIn: Double = 1.5
    var fadeOut: Double = 1.5
}

/// Formats `AVAudioFile` can open. Ogg Vorbis and Opus are deliberately absent — AVFoundation
/// cannot read them, and silently skipping such files is worse than reporting them.
enum AudioFormats {
    static let playable: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4", "m4b", "alac"]
    static let knownUnplayable: Set<String> = ["ogg", "oga", "opus", "wma", "webm"]
}

/// Scene storage with a **folder-per-scene** fallback: with no `scenes.json`, every subfolder
/// of `~/DMConsole/audio` becomes a scene and its files become equal-gain layers. That makes
/// the app useful the moment files are dropped in, before any scene has been authored.
enum SceneLibrary {
    /// Set when a `scenes.json` exists but could not be read, so the UI can say so instead of
    /// quietly showing folder-derived scenes that look like data loss.
    private(set) nonisolated(unsafe) static var lastError: String?

    static func load() -> [SoundScene] {
        lastError = nil
        guard let data = try? Data(contentsOf: Vault.scenesFile) else {
            return derivedFromFolders()
        }
        do {
            let scenes = try JSONDecoder().decode([SoundScene].self, from: data)
            return scenes.isEmpty ? derivedFromFolders() : scenes
        } catch {
            lastError = "scenes.json could not be read (\(error.localizedDescription)). "
                      + "Showing folder-derived scenes; your file has not been changed."
            return derivedFromFolders()
        }
    }

    static func save(_ scenes: [SoundScene]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(scenes).write(to: Vault.scenesFile, options: .atomic)
    }

    /// Files whose extension we know AVFoundation cannot decode, so the UI can say so.
    static func unplayableFiles() -> [String] {
        walk().filter { AudioFormats.knownUnplayable.contains($0.pathExtension.lowercased()) }
            .map { $0.lastPathComponent }
    }

    static func derivedFromFolders() -> [SoundScene] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: Vault.audio,
                                                       includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles])
        else { return [] }

        let symbols = ["cloud.rain", "flame", "wind", "building.columns", "moon.stars",
                       "bolt", "drop", "leaf", "hammer", "shield"]

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .enumerated()
            .map { index, dir in
                let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles])) ?? []
                let layers = files
                    .filter { AudioFormats.playable.contains($0.pathExtension.lowercased()) }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    .map { AudioLayer(file: "\(dir.lastPathComponent)/\($0.lastPathComponent)") }

                return SoundScene(name: dir.lastPathComponent,
                                  symbol: symbols[index % symbols.count],
                                  layers: layers)
            }
            .filter { !$0.layers.isEmpty }
    }

    private static func walk() -> [URL] {
        guard let e = FileManager.default.enumerator(at: Vault.audio,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }
    }
}
