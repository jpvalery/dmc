import Observation
import Foundation

/// One session's notes: a plain markdown file in the campaign's `notes/` folder.
///
/// Named `YYYY-MM-DD.md`, optionally with a title after the date. Keeping the date first means
/// the filenames sort chronologically on their own, and the files stay greppable from a terminal
/// without the app running.
struct SessionNote: Identifiable, Hashable {
    var id: String { fileName }
    let fileName: String
    let modified: Date

    var url: URL { Vault.notes.appending(path: fileName) }

    /// `2026-09-07 Into the Underdark.md` → date `2026-09-07`, title `Into the Underdark`.
    private var stem: String { (fileName as NSString).deletingPathExtension }
    var date: String { String(stem.prefix(10)) }
    var title: String {
        let rest = stem.dropFirst(10).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? date : rest
    }

    var displayName: String { title == date ? date : "\(date) · \(title)" }
}

/// A request for the editor to insert text at the cursor. A fresh `id` each time, so asking for
/// the same text twice still counts as two requests.
struct InsertRequest: Equatable {
    let id = UUID()
    let text: String
}

@MainActor
@Observable final class NotesStore {
    enum Status: Equatable {
        case idle, editing, saved, failed(String)
    }

    private(set) var sessions: [SessionNote] = []
    private(set) var selected: SessionNote?
    private(set) var status: Status = .idle

    /// The document being edited. Every mutation restarts the autosave timer.
    var text: String = "" {
        didSet { scheduleSave() }
    }

    /// Set by `insert(_:)`, consumed by the editor.
    private(set) var insertRequest: InsertRequest?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Set while `text` is being replaced programmatically, so loading a file is not mistaken
    /// for the user typing and does not immediately write it back.
    @ObservationIgnored private var isLoading = false

    @ObservationIgnored private static let debounce = Duration.milliseconds(800)

    init() {
        Vault.bootstrap()
        reload()
    }

    /// Fixed locale and calendar: with a non-Gregorian system calendar a bare `yyyy` would write
    /// that calendar's year into the filename, and the sessions would stop sorting.
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }

    static var todayFileName: String {
        formatter("yyyy-MM-dd").string(from: Date()) + ".md"
    }

    /// Rescan the notes folder for the list, leaving what is open alone.
    private func refreshSessions() {
        try? FileManager.default.createDirectory(at: Vault.notes, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Vault.notes,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []

        sessions = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return SessionNote(fileName: url.lastPathComponent, modified: modified)
            }
            // Newest first: the session you want is nearly always the last one you touched.
            .sorted { $0.fileName > $1.fileName }
    }

    /// Rescan the campaign's notes folder, keeping the current selection if it still exists.
    func reload() {
        refreshSessions()

        if let current = selected, let again = sessions.first(where: { $0.id == current.id }) {
            load(again)
        } else if let first = sessions.first {
            load(first)
        } else {
            selected = nil
            replaceText("")
        }
    }

    func select(_ session: SessionNote) {
        guard session.id != selected?.id else { return }
        saveNow()
        load(session)
    }

    /// Opens today's session, creating it if this is the first note of the day.
    func openToday() {
        saveNow()
        let name = Self.todayFileName
        if let existing = sessions.first(where: { $0.fileName == name }) {
            load(existing)
            return
        }
        let url = Vault.notes.appending(path: name)
        let heading = "# \(String(name.dropLast(3)))\n\n"
        do {
            try heading.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Diagnostics.shared.report("Could not create today's session note: \(error.localizedDescription)")
        }
        reload()
        if let created = sessions.first(where: { $0.fileName == name }) { load(created) }
    }

    func rename(_ session: SessionNote, to title: String) {
        saveNow()
        let clean = title
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
        let name = clean.isEmpty ? "\(session.date).md" : "\(session.date) \(clean).md"
        guard name != session.fileName else { return }
        let destination = Vault.notes.appending(path: name)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        do {
            try FileManager.default.moveItem(at: session.url, to: destination)
        } catch {
            Diagnostics.shared.report("Could not rename “\(session.title)”: \(error.localizedDescription)")
            return
        }
        selected = nil
        reload()
        if let renamed = sessions.first(where: { $0.fileName == name }) { load(renamed) }
    }

    /// Moves the note to the Trash rather than deleting it, so it can be put back.
    func delete(_ session: SessionNote) {
        do {
            try FileManager.default.trashItem(at: session.url, resultingItemURL: nil)
        } catch {
            Log.persistence.error("trash \(session.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            Diagnostics.shared.report("Could not move “\(session.title)” to the Trash: \(error.localizedDescription)")
            return
        }
        if selected?.id == session.id { selected = nil }
        reload()
    }

    /// Flush immediately — on ⌘S, before switching away, and at quit.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let session = selected else { return }
        do {
            try text.write(to: session.url, atomically: true, encoding: .utf8)
            status = .saved
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Insertion and the session log

    /// Asks the editor to put `text` at the cursor.
    func insert(_ text: String) {
        insertRequest = InsertRequest(text: text)
    }

    /// Adds `- 20:14 event` under the `## Log` heading of today's session, creating the note and
    /// the heading if need be. If today's note is the one on screen the edit goes through the
    /// editor's own text, so it is not overwritten by the next autosave; otherwise the file is
    /// appended to on disk and the open note is left alone.
    func appendLog(_ event: String) {
        let line = "- \(Self.formatter("HH:mm").string(from: Date())) \(event)"
        let name = Self.todayFileName

        if selected?.fileName == name {
            text = Self.inserting(line, intoLogOf: text)
            return
        }

        let url = Vault.notes.appending(path: name)
        let existing = (try? String(contentsOf: url, encoding: .utf8))
            ?? "# \(String(name.dropLast(3)))\n\n"
        do {
            try Self.inserting(line, intoLogOf: existing).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Diagnostics.shared.report("Could not write to the session log: \(error.localizedDescription)")
            return
        }
        if selected == nil { reload() } else { refreshSessions() }
    }

    /// Puts `line` at the end of the `## Log` section — before whatever heading follows it — or
    /// starts the section at the end of the note when there isn't one.
    static func inserting(_ line: String, intoLogOf text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let heading = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased() == "## log"
        }) else {
            var out = text
            if !out.hasSuffix("\n") { out += "\n" }
            return out + "\n## Log\n\(line)\n"
        }

        var end = lines.count
        if heading + 1 < lines.count,
           let next = lines[(heading + 1)...].firstIndex(where: { $0.hasPrefix("#") }) {
            end = next
        }
        var at = end
        while at > heading + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
        lines.insert(line, at: at)
        return lines.joined(separator: "\n")
    }

    private func load(_ session: SessionNote) {
        selected = session
        replaceText((try? String(contentsOf: session.url, encoding: .utf8)) ?? "")
        status = .idle
    }

    private func replaceText(_ value: String) {
        isLoading = true
        text = value
        isLoading = false
    }

    private func scheduleSave() {
        guard !isLoading, selected != nil else { return }
        status = .editing
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: NotesStore.debounce)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
