import AVFoundation
import Combine
import Foundation

/// One playable file in the vault.
struct SoundFile: Identifiable, Hashable {
    var id: String { relativePath }
    /// Relative to `Vault.audio`, which is also how `AudioLayer.file` stores it.
    let relativePath: String
    let name: String
    let folder: String
    let duration: Double

    var displayFolder: String { folder.isEmpty ? "—" : folder }

    var durationText: String {
        guard duration > 0 else { return "" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Recursive index of everything playable in `~/DMConsole/audio`.
///
/// Durations come from `AVAudioFile`, which has to crack each file open, so results are cached
/// in `library.json` keyed by size and modification date — a rescan of an unchanged library
/// costs no decoding at all.
@MainActor
final class SoundLibrary: ObservableObject {
    @Published private(set) var files: [SoundFile] = []
    @Published private(set) var unplayable: [String] = []
    @Published private(set) var isScanning = false

    private struct CacheEntry: Codable {
        let duration: Double
        let size: Int64
        let modified: Double
    }
    private var cache: [String: CacheEntry] = [:]

    init() {
        Vault.bootstrap()
        loadCache()
        Task { await scan() }
    }

    var folders: [String] {
        Array(Set(files.map(\.folder))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let (found, bad, newCache) = await Task.detached(priority: .utility) { [cache] in
            Self.performScan(cache: cache)
        }.value

        files = found
        unplayable = bad
        cache = newCache
        saveCache()
    }

    /// Runs off the main actor: touching hundreds of files and decoding headers.
    private nonisolated static func performScan(
        cache: [String: CacheEntry]
    ) -> ([SoundFile], [String], [String: CacheEntry]) {
        let fm = FileManager.default
        let base = Vault.audio
        guard let walker = fm.enumerator(at: base,
                                         includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                         options: [.skipsHiddenFiles]) else { return ([], [], cache) }

        var found: [SoundFile] = []
        var bad: [String] = []
        var next: [String: CacheEntry] = [:]

        for case let url as URL in walker {
            let ext = url.pathExtension.lowercased()
            let relative = url.path.replacingOccurrences(of: base.path + "/", with: "")

            if AudioFormats.knownUnplayable.contains(ext) { bad.append(relative); continue }
            guard AudioFormats.playable.contains(ext) else { continue }

            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0

            let duration: Double
            if let hit = cache[relative], hit.size == size, hit.modified == modified {
                duration = hit.duration
            } else if let file = try? AVAudioFile(forReading: url) {
                duration = Double(file.length) / file.processingFormat.sampleRate
            } else {
                bad.append(relative)
                continue
            }

            next[relative] = CacheEntry(duration: duration, size: size, modified: modified)
            let folder = (relative as NSString).deletingLastPathComponent
            found.append(SoundFile(relativePath: relative,
                                   name: url.deletingPathExtension().lastPathComponent,
                                   folder: folder,
                                   duration: duration))
        }

        found.sort {
            $0.folder == $1.folder
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.folder.localizedStandardCompare($1.folder) == .orderedAscending
        }
        return (found, bad, next)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Vault.libraryFile),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data)
        else { return }
        cache = decoded
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Vault.libraryFile, options: .atomic)
    }
}
