import Combine
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

@MainActor
final class NotesStore: ObservableObject {
    enum Status: Equatable {
        case idle, editing, saved, failed(String)
    }

    @Published private(set) var sessions: [SessionNote] = []
    @Published private(set) var selected: SessionNote?
    @Published private(set) var status: Status = .idle

    /// The document being edited. Every mutation restarts the autosave timer.
    @Published var text: String = "" {
        didSet { scheduleSave() }
    }

    private var saveTask: Task<Void, Never>?
    /// Set while `text` is being replaced programmatically, so loading a file is not mistaken
    /// for the user typing and does not immediately write it back.
    private var isLoading = false

    private static let debounce = Duration.milliseconds(800)

    init() {
        Vault.bootstrap()
        reload()
    }

    static var todayFileName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date()) + ".md"
    }

    /// Rescan the campaign's notes folder, keeping the current selection if it still exists.
    func reload() {
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
        try? heading.write(to: url, atomically: true, encoding: .utf8)
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
        try? FileManager.default.moveItem(at: session.url, to: destination)
        selected = nil
        reload()
        if let renamed = sessions.first(where: { $0.fileName == name }) { load(renamed) }
    }

    func delete(_ session: SessionNote) {
        try? FileManager.default.removeItem(at: session.url)
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
