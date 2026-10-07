import Foundation

/// Something a note can do when clicked.
///
/// Written into the notes as `[[scene:Tavern]]`, `[[effect:Door slam]]` or `[[stop]]`, so a
/// session's prep can double as its run sheet: read down the page, click the cue.
enum NoteTrigger: Equatable {
    case scene(String)
    case effect(String)
    case stopAll

    /// The text that stands for this trigger in a note.
    var markup: String {
        switch self {
        case .scene(let name): "[[scene:\(name)]]"
        case .effect(let name): "[[effect:\(name)]]"
        case .stopAll: "[[stop]]"
        }
    }
}

enum NoteLinks {
    /// `[[scene:Name]]`, `[[effect:Name]]`, `[[stop]]` — case-insensitive, spaces around the colon
    /// tolerated.
    static let pattern = try! NSRegularExpression(
        pattern: #"\[\[\s*(scene|effect|stop)\s*(?::\s*([^\]\n]*?))?\s*\]\]"#,
        options: [.caseInsensitive])

    /// The trigger a matched `[[…]]` stands for, if it is well formed.
    static func trigger(kind: String, name: String?) -> NoteTrigger? {
        let clean = name?.trimmingCharacters(in: .whitespaces) ?? ""
        switch kind.lowercased() {
        case "scene": return clean.isEmpty ? nil : .scene(clean)
        case "effect": return clean.isEmpty ? nil : .effect(clean)
        case "stop": return .stopAll
        default: return nil
        }
    }

    /// Finds the entry `name` means: an exact match ignoring case first, then a name that starts
    /// with it, then one that merely contains it — but only if that is unambiguous, so a vague
    /// cue never plays the wrong scene.
    static func match(_ name: String, in names: [String]) -> Int? {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return nil }
        let lowered = names.map { $0.lowercased() }

        if let exact = lowered.firstIndex(of: needle) { return exact }
        for test in [{ (n: String) in n.hasPrefix(needle) }, { (n: String) in n.contains(needle) }] {
            let hits = lowered.indices.filter { test(lowered[$0]) }
            if hits.count == 1 { return hits[0] }
            if hits.count > 1 { return nil }
        }
        return nil
    }
}
