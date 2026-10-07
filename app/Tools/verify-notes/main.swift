import Foundation

@main
struct Probe {
    @MainActor
    static func main() async {
        let vault = CommandLine.arguments[1]
        UserDefaults.standard.set(vault, forKey: "vault.path")
        Vault.bootstrap()

        var fails = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("  \(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            if !ok { fails += 1 }
        }

        let store = NotesStore()
        check("starts with no sessions", store.sessions.isEmpty)

        store.openToday()
        check("today's session created", store.selected != nil, store.selected?.fileName ?? "none")
        check("filename is YYYY-MM-DD.md",
              store.selected?.fileName.range(of: #"^\d{4}-\d{2}-\d{2}\.md$"#,
                                             options: .regularExpression) != nil)

        // Type, then let the debounce fire on its own — no explicit save.
        store.text = "# Session one\n\nThe party enters the crypt.\n"
        check("status shows editing while typing", store.status == .editing)
        try? await Task.sleep(for: .milliseconds(1200))
        check("autosaved without an explicit save", store.status == .saved)

        let url = store.selected!.url
        let onDisk = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        check("file content matches the editor", onDisk == store.text)
        check("file is plain markdown", onDisk.hasPrefix("# Session one"))

        // Force-quit and relaunch: a brand new store reading the same folder.
        let relaunched = NotesStore()
        check("survives a relaunch", relaunched.text == store.text,
              "\(relaunched.text.count) chars recovered")
        check("reopens the same session", relaunched.selected?.fileName == store.selected?.fileName)

        // A second session, and switching between them.
        let second = Vault.notes.appending(path: "2020-01-02 Old Session.md")
        try? "# Older\n\nnotes from before\n".write(to: second, atomically: true, encoding: .utf8)
        relaunched.reload()
        check("both sessions listed", relaunched.sessions.count == 2,
              relaunched.sessions.map(\.fileName).joined(separator: ", "))
        check("newest sorts first", relaunched.sessions.first?.fileName == store.selected?.fileName)

        let old = relaunched.sessions.last!
        check("title parsed from filename", old.title == "Old Session", old.title)
        relaunched.select(old)
        check("switching loads the other file", relaunched.text.hasPrefix("# Older"))

        // Editing then switching away must not lose the edit.
        relaunched.text = "# Older\n\nedited before switching\n"
        relaunched.select(relaunched.sessions.first!)
        let oldOnDisk = (try? String(contentsOf: old.url, encoding: .utf8)) ?? ""
        check("switching away flushes the edit", oldOnDisk.contains("edited before switching"))

        // Rename keeps the date prefix.
        relaunched.select(old)
        relaunched.rename(old, to: "Crypt of the Wyrm")
        check("renamed, date kept",
              relaunched.selected?.fileName == "2020-01-02 Crypt of the Wyrm.md",
              relaunched.selected?.fileName ?? "none")
        check("content survived the rename", relaunched.text.contains("edited before switching"))

        // MARK: The session log
        func logOf(_ text: String) -> [String] {
            var inLog = false
            var out: [String] = []
            for line in text.components(separatedBy: "\n") {
                if line.hasPrefix("#") { inLog = line.lowercased() == "## log"; continue }
                if inLog, line.hasPrefix("- ") { out.append(String(line.dropFirst(8))) }   // past "- HH:mm "
            }
            return out
        }
        check("a heading is created when the note has none",
              NotesStore.inserting("- 20:14 Round 1", intoLogOf: "# Session\n\nText\n")
                  == "# Session\n\nText\n\n## Log\n- 20:14 Round 1\n")
        let one = NotesStore.inserting("- 20:14 a", intoLogOf: "# S\n")
        let two = NotesStore.inserting("- 20:15 b", intoLogOf: one)
        check("later lines follow earlier ones", two.hasSuffix("## Log\n- 20:14 a\n- 20:15 b\n"), two)
        let middle = NotesStore.inserting("- 20:16 c", intoLogOf: "## Log\n- 20:14 a\n\n## Loot\n- sword\n")
        check("a line goes at the end of the log, before the next heading",
              middle == "## Log\n- 20:14 a\n- 20:16 c\n\n## Loot\n- sword\n", middle)
        let heading = NotesStore.inserting("- 20:17 d", intoLogOf: "# S\n\n## Log")
        check("a log heading at the very end still works", heading == "# S\n\n## Log\n- 20:17 d", heading)

        // Today's note is the one open: the log goes through the editor's own text.
        let logStore = NotesStore()
        logStore.openToday()
        logStore.appendLog("Scene: Tavern")
        check("logging into the open note edits its text", logOf(logStore.text) == ["Scene: Tavern"],
              logStore.text)
        logStore.appendLog("Round 2")
        check("and appends in order", logOf(logStore.text) == ["Scene: Tavern", "Round 2"])
        logStore.saveNow()
        let logged = (try? String(contentsOf: logStore.selected!.url, encoding: .utf8)) ?? ""
        check("the log reaches the file", logOf(logged) == ["Scene: Tavern", "Round 2"])

        // Another note is open: today's file is appended to on disk, and the open note is left alone.
        let other = logStore.sessions.first { $0.fileName != NotesStore.todayFileName }
        if let other {
            logStore.select(other)
            let before = logStore.text
            logStore.appendLog("Combat started")
            let todayURL = Vault.notes.appending(path: NotesStore.todayFileName)
            let todayText = (try? String(contentsOf: todayURL, encoding: .utf8)) ?? ""
            check("logging while another note is open writes to today's file",
                  logOf(todayText) == ["Scene: Tavern", "Round 2", "Combat started"], todayText)
            check("and leaves the open note alone", logStore.text == before)
        }

        // Cues in the notes.
        let scenes = ["Tavern", "Tavern Brawl", "Crypt", "The Underdark"]
        check("a cue matches ignoring case", NoteLinks.match("crypt", in: scenes) == 2)
        check("an exact name beats a longer one that starts with it", NoteLinks.match("Tavern", in: scenes) == 0)
        check("a unique prefix matches", NoteLinks.match("the u", in: scenes) == 3)
        check("a unique fragment matches even mid-name", NoteLinks.match("under", in: scenes) == 3)
        check("an ambiguous fragment matches nothing", NoteLinks.match("tav", in: scenes) == nil)
        check("a unique fragment inside a name matches", NoteLinks.match("rypt", in: scenes) == 2)
        check("nothing matches nothing", NoteLinks.match("dragon", in: scenes) == nil
              && NoteLinks.match("  ", in: scenes) == nil)

        let sample = "Open on [[scene: Tavern]] then [[effect:Door slam]]; [[ STOP ]] and [[scene:]] and [[nonsense]]"
        let range = NSRange(location: 0, length: (sample as NSString).length)
        let found = NoteLinks.pattern.matches(in: sample, range: range).compactMap { m -> NoteTrigger? in
            let kind = (sample as NSString).substring(with: m.range(at: 1))
            let name = m.range(at: 2).location == NSNotFound ? nil : (sample as NSString).substring(with: m.range(at: 2))
            return NoteLinks.trigger(kind: kind, name: name)
        }
        check("cues parse from a page", found == [.scene("Tavern"), .effect("Door slam"), .stopAll], "\(found)")
        check("a cue round-trips through its markup", NoteTrigger.scene("Crypt").markup == "[[scene:Crypt]]")

        print(fails == 0 ? "\n  all notepad checks pass" : "\n  \(fails) FAILED")
    }
}
