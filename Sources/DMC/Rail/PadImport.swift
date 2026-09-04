import SwiftUI

/// `.sheet(item:)` needs an Identifiable; a layer id is already unique.
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

/// Rebuilds a saved Tabletop Audio SoundPad layout as a DMC scene.
///
/// The arrangement — which slots, at what level, looping or one-shot — is the DM's own work and
/// is what this preserves. The pad's audio is not fetched: those sounds are excluded by their
/// author from download and from use off tabletopaudio.com, unlike the 10-minute ambiences.
/// Each imported slot therefore arrives unbound, ready to point at a file you hold.
enum PadImport {
    struct Slot {
        let padID: String
        let gain: Double
        let loops: Bool
    }

    struct Result {
        let slots: [Slot]
        let skipped: Int
        var looping: Int { slots.filter(\.loops).count }
        var oneShots: Int { slots.filter { !$0.loops }.count }
    }

    /// A shared pad link, e.g. `https://ttaud.io/4x8Fyzx`, which redirects to
    /// `custom_sp.html?<name>&<id>,<vol>,<loop>,<freq>,&…`. The query carries the *layout* only —
    /// slot ids, levels and loop flags — so this is the same kind of import as the JSON, just
    /// pasted straight from the share button.
    static func parseShareLink(_ urlString: String) -> (name: String?, result: Result)? {
        guard let queryStart = urlString.firstIndex(of: "?") else { return nil }
        let query = String(urlString[urlString.index(after: queryStart)...])
            .removingPercentEncoding ?? String(urlString[urlString.index(after: queryStart)...])

        var groups = query.components(separatedBy: "&").filter { !$0.isEmpty }
        guard !groups.isEmpty else { return nil }

        // A leading group with no commas is the pad's name.
        var name: String?
        if let first = groups.first, !first.contains(",") {
            name = first.trimmingCharacters(in: .whitespaces)
            groups.removeFirst()
        }

        var slots: [Slot] = []
        var skipped = 0
        for group in groups {
            let parts = group.components(separatedBy: ",")
            guard parts.count >= 3, !parts[0].isEmpty, parts[0] != "0",
                  let gain = Double(parts[1]) else {
                skipped += 1
                continue
            }
            slots.append(Slot(padID: parts[0],
                              gain: min(max(gain, 0), 1),
                              loops: parts[2] == "1"))
        }
        guard !slots.isEmpty else { return nil }
        return (name, Result(slots: slots, skipped: skipped))
    }

    /// Short links redirect to the real query, so the final URL is what matters.
    static func resolve(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return response.url?.absoluteString
    }

    /// The JSON export is stringly typed: volumes and loop flags arrive as strings, and empty pad
    /// positions appear as id "0" with the literal string "null" in every other field.
    static func parse(_ text: String) -> Result? {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        var slots: [Slot] = []
        var skipped = 0

        for entry in raw {
            let id = string(entry["id"])
            let volume = string(entry["vol"])
            guard !id.isEmpty, id != "0", volume != "null", let gain = Double(volume) else {
                skipped += 1
                continue
            }
            slots.append(Slot(padID: id,
                              gain: min(max(gain, 0), 1),
                              loops: string(entry["loop"]) == "1"))
        }
        return slots.isEmpty ? nil : Result(slots: slots, skipped: skipped)
    }

    private static func string(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    static func scene(named name: String, from result: Result) -> SoundScene {
        SoundScene(name: name,
                   symbol: "square.grid.3x3",
                   layers: result.slots.map {
                       AudioLayer(file: "", gain: $0.gain, loops: $0.loops, padID: $0.padID)
                   })
    }
}

struct PadImportView: View {
    let onImport: (SoundScene) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var name = "Imported pad"
    @State private var fetched: PadImport.Result?
    @State private var isFetching = false
    @State private var fetchError: String?

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var looksLikeLink: Bool { trimmed.lowercased().hasPrefix("http") }

    /// A pasted link parses locally when it already carries the query; a short link needs one
    /// round trip to follow the redirect first.
    private var parsed: PadImport.Result? {
        if looksLikeLink {
            if let (_, result) = PadImport.parseShareLink(trimmed) { return result }
            return fetched
        }
        return PadImport.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import a SoundPad layout").font(.headline)

            Text("Paste a share link (ttaud.io/… or custom_sp.html?…) or the JSON from a saved "
                 + "pad. Levels and loop settings come across; each slot then needs a sound "
                 + "assigned from your own library.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Scene name", text: $name).textFieldStyle(.roundedBorder)

            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 170)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
                .onChange(of: text) { _, _ in fetched = nil; fetchError = nil }

            statusLine

            HStack {
                if looksLikeLink && parsed == nil {
                    Button(isFetching ? "Opening…" : "Open link") { Task { await fetch() } }
                        .disabled(isFetching)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Import") {
                    if let parsed { onImport(PadImport.scene(named: name, from: parsed)) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsed == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private var statusLine: some View {
        if isFetching {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Following the link…").font(.caption).foregroundStyle(.secondary)
            }
        } else if let error = fetchError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        } else if let parsed {
            Label("\(parsed.slots.count) slots — \(parsed.looping) looping, "
                  + "\(parsed.oneShots) one-shot"
                  + (parsed.skipped > 0 ? ", \(parsed.skipped) empty skipped" : ""),
                  systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        } else if !trimmed.isEmpty && !looksLikeLink {
            Label("That doesn't look like a SoundPad export.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func fetch() async {
        guard let url = URL(string: trimmed) else { return }
        isFetching = true
        fetchError = nil
        defer { isFetching = false }

        guard let finalURL = await PadImport.resolve(url) else {
            fetchError = "Couldn't reach that link."
            return
        }
        guard let (linkName, result) = PadImport.parseShareLink(finalURL) else {
            fetchError = "That link doesn't carry a pad layout."
            return
        }
        fetched = result
        // The share link names the pad; use it unless a name was already typed.
        if let linkName, !linkName.isEmpty, name == "Imported pad" { name = linkName }
    }
}
