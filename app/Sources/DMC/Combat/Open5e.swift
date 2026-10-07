import Foundation

/// A monster from Open5e (https://open5e.com), which serves the SRD and a number of open-licensed
/// third-party books. Only what the tracker needs is read: a name, AC, HP and Dexterity.
struct Open5eMonster: Identifiable, Hashable, Decodable {
    let name: String
    let armorClass: Int?
    let hitPoints: Int?
    let dexterity: Int?
    let challenge: String?
    let size: String?
    let kind: String?
    let sourceSlug: String?
    let source: String?

    var id: String { "\(sourceSlug ?? "")/\(name)" }

    /// Dexterity modifier, which is what initiative adds: (score − 10) / 2, rounded down.
    var initiativeBonus: Int? {
        dexterity.map { Int((Double($0 - 10) / 2).rounded(.down)) }
    }

    /// "Small humanoid · CR 1/4", for the row under the name.
    var summary: String {
        let body = [size, kind?.lowercased()].compactMap { $0 }.joined(separator: " ")
        let cr = challenge.map { "CR \($0)" }
        return [body.isEmpty ? nil : body, cr].compactMap { $0 }.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case name, size
        case armorClass = "armor_class"
        case hitPoints = "hit_points"
        case dexterity
        case challenge = "challenge_rating"
        case kind = "type"
        case sourceSlug = "document__slug"
        case source = "document__title"
    }
}

enum Open5eClient {
    private struct Page: Decodable { let results: [Open5eMonster] }

    private static let base = URL(string: "https://api.open5e.com/v1/monsters/")!
    private static let fields = "name,size,type,armor_class,hit_points,dexterity,challenge_rating,"
        + "document__slug,document__title"

    /// Monsters whose name contains `query`, the SRD first and exact matches above everything.
    static func search(_ query: String) async throws -> [Open5eMonster] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return [] }

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "name__icontains", value: needle),
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "limit", value: "30"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let monsters = try JSONDecoder().decode(Page.self, from: data).results

        func rank(_ m: Open5eMonster) -> Int {
            let exact = m.name.caseInsensitiveCompare(needle) == .orderedSame ? 0 : 2
            return exact + (m.sourceSlug == "wotc-srd" ? 0 : 1)
        }
        return monsters.sorted {
            rank($0) != rank($1) ? rank($0) < rank($1)
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
