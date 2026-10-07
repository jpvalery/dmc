import Foundation

/// Every JSON file the app owns is read and written through here.
///
/// Three things the call sites used to get wrong, each of them quietly:
///
/// 1. **A file that fails to decode was treated as an empty one.** The next ordinary edit then
///    wrote the empty state back over the original, destroying whatever the decoder had choked
///    on. Now the unreadable file is copied aside first — the original is left where it is —
///    and the failure is reported.
/// 2. **One bad element lost the whole array.** Scenes and effects decode element by element, so
///    a single malformed entry is skipped (and the file backed up) instead of taking every other
///    scene with it.
/// 3. **Write failures were swallowed.** They are logged and surfaced now.
///
/// Saves can also keep rolling snapshots, so a scene deleted by mistake is a file copy away.
enum JSONStore {
    enum Loaded<Value> {
        /// No file yet: first run, or nothing saved.
        case missing
        case ok(Value)
        /// Something was wrong. `value` holds whatever could still be recovered, and `backup` is
        /// the copy of the original, when one could be made.
        case damaged(value: Value?, backup: URL?, reason: String)
    }

    // MARK: Load

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> Loaded<T> {
        guard let data = read(url) else {
            return FileManager.default.fileExists(atPath: url.path)
                ? damaged(url, value: nil, reason: "the file could not be read")
                : .missing
        }
        do {
            return .ok(try JSONDecoder().decode(T.self, from: data))
        } catch {
            return damaged(url, value: nil, reason: describe(error))
        }
    }

    /// Decodes an array, keeping every element that decodes and reporting the rest.
    static func loadLossy<Element: Decodable>(_ type: Element.Type, from url: URL) -> Loaded<[Element]> {
        guard let data = read(url) else {
            return FileManager.default.fileExists(atPath: url.path)
                ? damaged(url, value: nil, reason: "the file could not be read")
                : .missing
        }
        do {
            let wrapped = try JSONDecoder().decode([Lossy<Element>].self, from: data)
            let kept = wrapped.compactMap(\.value)
            if kept.count == wrapped.count { return .ok(kept) }
            let dropped = wrapped.count - kept.count
            return damaged(url, value: kept,
                           reason: "\(dropped) of \(wrapped.count) entries could not be read")
        } catch {
            return damaged(url, value: nil, reason: describe(error))
        }
    }

    private struct Lossy<Element: Decodable>: Decodable {
        let value: Element?
        init(from decoder: Decoder) throws {
            value = try? Element(from: decoder)
        }
    }

    private static func read(_ url: URL) -> Data? {
        do { return try Data(contentsOf: url) } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                Log.persistence.error("read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    private static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .dataCorrupted(let c): return c.debugDescription
            case .keyNotFound(let key, _): return "missing key “\(key.stringValue)”"
            case .typeMismatch(_, let c), .valueNotFound(_, let c):
                return c.debugDescription
            @unknown default: break
            }
        }
        return error.localizedDescription
    }

    private static func damaged<V>(_ url: URL, value: V?, reason: String) -> Loaded<V> {
        let backup = backUpDamaged(url)
        let name = url.lastPathComponent
        var message = "\(name) has a problem (\(reason))."
        if let backup { message += " A copy was kept as \(backup.lastPathComponent)." }
        Log.persistence.error("\(message, privacy: .public)")
        reportIssue(message)
        return .damaged(value: value, backup: backup, reason: reason)
    }

    // MARK: Damaged-file backup

    /// Copies the file next to itself as `name.corrupt-<stamp>.json`. Copied, never moved, so
    /// the original is still there to be fixed by hand. A file already backed up byte-for-byte
    /// is not copied again, or every launch with the same broken file would add another.
    @discardableResult
    static func backUpDamaged(_ url: URL) -> URL? {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: url) else { return nil }

        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        let prefix = "\(stem).corrupt-"

        let siblings = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for existing in siblings where existing.lastPathComponent.hasPrefix(prefix) {
            if let old = try? Data(contentsOf: existing), old == data { return existing }
        }

        // The stamp only resolves to the second, so two different damaged files can land on the
        // same name; number the later one rather than fail to copy it.
        var destination = folder.appending(path: "\(prefix)\(stamp()).\(ext)")
        var n = 2
        while fm.fileExists(atPath: destination.path) {
            destination = folder.appending(path: "\(prefix)\(stamp())-\(n).\(ext)")
            n += 1
        }
        do {
            try fm.copyItem(at: url, to: destination)
            return destination
        } catch {
            Log.persistence.error("backup of \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Save

    @discardableResult
    static func save<T: Encodable>(_ value: T, to url: URL, snapshots: Bool = false) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            if snapshots { snapshot(of: url, replacingWith: data) }
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            let message = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
            Log.persistence.error("\(message, privacy: .public)")
            reportIssue(message)
            return false
        }
    }

    // MARK: Rolling snapshots

    /// At most one snapshot per interval, newest `keep` retained. Taken *before* the write, from
    /// what is on disk, so it is always the state being replaced.
    private static let snapshotInterval: TimeInterval = 10 * 60
    private static let keep = 30

    private static func snapshot(of url: URL, replacingWith new: Data) {
        let fm = FileManager.default
        guard let old = try? Data(contentsOf: url), old != new else { return }

        let folder = url.deletingLastPathComponent().appending(path: "backups", directoryHint: .isDirectory)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let prefix = "\(stem)-"

        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return }

        let mine = ((try? fm.contentsOfDirectory(at: folder,
                                                 includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == ext }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if let newest = mine.last,
           let modified = (try? newest.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate,
           Date().timeIntervalSince(modified) < snapshotInterval {
            return
        }

        try? old.write(to: folder.appending(path: "\(prefix)\(stamp()).\(ext)"), options: .atomic)
        for stale in mine.dropLast(keep - 1) { try? fm.removeItem(at: stale) }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
