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

        print(fails == 0 ? "\n  all notepad checks pass" : "\n  \(fails) FAILED")
    }
}
