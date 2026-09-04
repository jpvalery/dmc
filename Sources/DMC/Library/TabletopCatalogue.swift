import Combine
import Foundation

/// One 10-minute ambience from tabletopaudio.com's public catalogue.
///
/// Only the 10-minute ambiences are covered by the site's CC BY-NC-ND 4.0 licence, which is why
/// this app fetches that catalogue and nothing else. The SoundPad sounds are explicitly excluded
/// by their author from download and from use off the site, so they are not touched here.
struct TTATrack: Identifiable, Hashable, Codable {
    let key: Int
    let title: String
    let type: String
    let genres: [String]
    let flavor: String
    let link: String
    let tags: [String]

    var id: Int { key }

    /// `key` plus a filesystem-safe title, so downloads sort the way the site numbers them.
    var fileName: String {
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return "\(key)_\(safe).mp3"
    }

    var relativePath: String { "\(TabletopAudio.folderName)/\(fileName)" }
    var localURL: URL { Vault.audio.appending(path: relativePath) }
    var isDownloaded: Bool { FileManager.default.fileExists(atPath: localURL.path) }

    var searchHaystack: String {
        ([title, type, flavor] + genres + tags).joined(separator: " ").lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case key, track_title, track_type, track_genre, flavor_text, link, tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The feed is loosely typed: `key` is sometimes a string, genres are sometimes a single
        // comma-joined string, and tags/flavour are occasionally absent.
        if let n = try? c.decode(Int.self, forKey: .key) {
            key = n
        } else if let s = try? c.decode(String.self, forKey: .key), let n = Int(s) {
            key = n
        } else {
            key = 0
        }
        title = (try? c.decode(String.self, forKey: .track_title)) ?? "Untitled"
        type = (try? c.decode(String.self, forKey: .track_type)) ?? ""
        flavor = (try? c.decode(String.self, forKey: .flavor_text)) ?? ""
        link = (try? c.decode(String.self, forKey: .link)) ?? ""

        let rawGenres = (try? c.decode([String].self, forKey: .track_genre)) ?? []
        genres = rawGenres
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(title, forKey: .track_title)
        try c.encode(type, forKey: .track_type)
        try c.encode(genres, forKey: .track_genre)
        try c.encode(flavor, forKey: .flavor_text)
        try c.encode(link, forKey: .link)
        try c.encode(tags, forKey: .tags)
    }
}

/// Non-isolated constants, so `TTATrack` (a plain struct) can reach them without hopping to
/// the main actor.
enum TabletopAudio {
    static let folderName = "Tabletop Audio"
    static let sourceURL = URL(string: "https://tabletopaudio.com/tta_data")!
    static var folder: URL { Vault.audio.appending(path: folderName, directoryHint: .isDirectory) }
    static var attributionFile: URL { folder.appending(path: "ATTRIBUTION.md") }
}

@MainActor
final class TabletopCatalogue: ObservableObject {

    @Published private(set) var tracks: [TTATrack] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private var cacheFile: URL { Vault.root.appending(path: "tabletop-catalogue.json") }

    private struct Feed: Codable { let tracks: [TTATrack] }

    init() { loadLocal() }

    /// Themed sets matching how a session actually gets run, so a new vault can be filled with
    /// something useful in one click rather than 523 individual decisions.
    struct Collection: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let symbol: String
        let tags: [String]
    }

    static let collections: [Collection] = [
        .init(name: "Dungeon", symbol: "square.split.bottomrightquarter",
              tags: ["dungeon", "cave", "crypt", "underground", "dripping"]),
        .init(name: "Dark Forest", symbol: "tree",
              tags: ["forest", "woods", "jungle", "swamp", "night", "dark"]),
        .init(name: "Olde Towne", symbol: "building.2",
              tags: ["town", "city", "market", "village", "medieval", "street"]),
        .init(name: "Combat", symbol: "shield",
              tags: ["combat", "battle", "war", "fight", "army", "siege"]),
        .init(name: "The Tavern", symbol: "cup.and.saucer",
              tags: ["tavern", "inn", "pub", "festive", "celebration"]),
        .init(name: "Castle Raven", symbol: "moon.stars",
              tags: ["castle", "gothic", "haunted", "ghosts", "vampire", "creepy"]),
        .init(name: "DM Tools", symbol: "wand.and.stars",
              tags: ["suspense", "tension", "mystery", "ominous"]),
    ]

    /// Rank by how many of the collection's tags a track carries, so the most on-theme tracks
    /// come first; newer keys break ties.
    func tracks(in collection: Collection, limit: Int) -> [TTATrack] {
        let wanted = Set(collection.tags)

        // Broken into steps deliberately: as one chained expression the type-checker times out.
        var scored: [(track: TTATrack, score: Int)] = []
        for track in tracks {
            let lowered: Set<String> = Set(track.tags.map { $0.lowercased() })
            let score: Int = lowered.intersection(wanted).count
            if score > 0 { scored.append((track, score)) }
        }
        scored.sort { a, b in
            a.score == b.score ? a.track.key > b.track.key : a.score > b.score
        }
        return scored.prefix(limit).map(\.track)
    }

    var allGenres: [String] {
        Array(Set(tracks.flatMap(\.genres))).sorted()
    }

    func refresh() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: TabletopAudio.sourceURL)
            let feed = try JSONDecoder().decode(Feed.self, from: data)
            tracks = feed.tracks.filter { !$0.link.isEmpty }
            try? data.write(to: cacheFile, options: .atomic)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func filtered(search: String, genre: String?, downloadedOnly: Bool) -> [TTATrack] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return tracks.filter { track in
            if let genre, !track.genres.contains(genre) { return false }
            if downloadedOnly, !track.isDownloaded { return false }
            guard !needle.isEmpty else { return true }
            return track.searchHaystack.contains(needle)
        }
    }

    /// Vault cache first (it is the freshest the user has fetched), then the snapshot shipped
    /// inside the app. Shipping a copy means the browser is populated on first launch and stays
    /// usable with no network at the table.
    private func loadLocal() {
        for url in [cacheFile, Bundle.main.url(forResource: "tta_data", withExtension: "json")] {
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let feed = try? JSONDecoder().decode(Feed.self, from: data),
                  !feed.tracks.isEmpty
            else { continue }
            tracks = feed.tracks
            return
        }
    }
}
