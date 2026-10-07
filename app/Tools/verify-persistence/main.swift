import Foundation

/// The bug this exists to keep fixed: a `scenes.json` that failed to decode was treated as empty,
/// so the first ordinary edit wrote the empty state back over it and the original was gone.
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
        let fm = FileManager.default
        func siblings(of url: URL, containing marker: String) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.contains(marker) }
        }
        func text(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

        // MARK: A broken scenes.json survives an edit
        let scenesFile = Vault.scenesFile
        let ruined = #"[{"name": "Tavern", "layers": [ this is not json"#
        try? ruined.write(to: scenesFile, atomically: true, encoding: .utf8)

        let store = SceneStore()
        check("a broken file does not stop the app starting", true)
        try? await Task.sleep(for: .milliseconds(200))
        check("the problem is reported", Diagnostics.shared.issues.contains { $0.contains("scenes.json") },
              Diagnostics.shared.issues.joined(separator: " | "))

        let backups = siblings(of: scenesFile, containing: "scenes.corrupt-")
        check("a backup copy was made", backups.count == 1, backups.map(\.lastPathComponent).joined(separator: ", "))
        check("the backup is the original, byte for byte", backups.first.map(text) == ruined)
        check("the original was not moved", text(scenesFile) == ruined)

        // The edit that used to destroy it.
        store.upsert(SoundScene(name: "Fresh scene", symbol: "waveform", layers: []))
        check("an ordinary edit writes a valid file now", {
            guard let data = try? Data(contentsOf: scenesFile) else { return false }
            return (try? JSONDecoder().decode([SoundScene].self, from: data))?.contains { $0.name == "Fresh scene" } == true
        }())
        check("…and the damaged original is still on disk, in its backup",
              siblings(of: scenesFile, containing: "scenes.corrupt-").first.map(text) == ruined)

        // The same broken file, loaded again, is not backed up a second time.
        try? ruined.write(to: scenesFile, atomically: true, encoding: .utf8)
        _ = SceneStore()
        _ = SceneStore()
        check("loading the same damaged file again adds no duplicate backup",
              siblings(of: scenesFile, containing: "scenes.corrupt-").count == 1)

        // MARK: One bad scene does not take the rest with it
        let partial = """
        [{"name": "Good one", "layers": []},
         {"name": 42, "layers": "nope"},
         {"name": "Good two", "layers": []}]
        """
        try? partial.write(to: scenesFile, atomically: true, encoding: .utf8)
        let lossy = SceneStore()
        check("the readable scenes are kept", lossy.scenes.map(\.name) == ["Good one", "Good two"],
              lossy.scenes.map(\.name).joined(separator: ", "))
        check("the file with the bad entry is backed up",
              siblings(of: scenesFile, containing: "scenes.corrupt-").contains { text($0) == partial })

        // MARK: Effects, which used to come back empty
        let effectsFile = Vault.effectsFile
        let badEffects = "{ definitely not an array"
        try? badEffects.write(to: effectsFile, atomically: true, encoding: .utf8)
        let effects = EffectStore()
        check("a broken effects file loads as empty without losing the original",
              effects.effects.isEmpty && text(effectsFile) == badEffects)
        check("and is backed up", siblings(of: effectsFile, containing: "effects.corrupt-").first.map(text) == badEffects)
        effects.upsert(SoundEffect(name: "Door", file: "door.wav"))
        check("adding an effect afterwards does not lose the backup",
              siblings(of: effectsFile, containing: "effects.corrupt-").first.map(text) == badEffects)

        // MARK: Rolling snapshots of a good file
        let snapshotsDir = scenesFile.deletingLastPathComponent().appending(path: "backups")
        try? fm.removeItem(at: snapshotsDir)
        try? fm.removeItem(at: scenesFile)
        let first = [SoundScene(name: "Version one")]
        JSONStore.save(first, to: scenesFile, snapshots: true)
        check("saving over nothing takes no snapshot", !fm.fileExists(atPath: snapshotsDir.path)
              || ((try? fm.contentsOfDirectory(atPath: snapshotsDir.path)) ?? []).filter { $0.hasPrefix("scenes-") }.isEmpty)
        JSONStore.save([SoundScene(name: "Version two")], to: scenesFile, snapshots: true)
        let taken = ((try? fm.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("scenes-") }
        check("the next save snapshots what it replaced", taken.count == 1
              && taken.first.map(text)?.contains("Version one") == true,
              taken.map(\.lastPathComponent).joined(separator: ", "))
        JSONStore.save([SoundScene(name: "Version three")], to: scenesFile, snapshots: true)
        let later = ((try? fm.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("scenes-") }
        check("a quick follow-up save does not add another", later.count == 1, "\(later.count)")
        check("the live file is the latest", text(scenesFile).contains("Version three"))

        // MARK: Failures are not silent
        let impossible = URL(filePath: "/nonexistent-dmc-test-folder/x.json")
        let wrote = JSONStore.save(["a"], to: impossible)
        try? await Task.sleep(for: .milliseconds(200))
        check("a failed save says so", !wrote && Diagnostics.shared.issues.contains { $0.contains("x.json") },
              Diagnostics.shared.issues.last ?? "none")

        // MARK: A missing file is not damage
        let before = Diagnostics.shared.issues.count
        if case .missing = JSONStore.load([String].self, from: Vault.root.appending(path: "nothing-here.json")) {
            check("a missing file is just missing", Diagnostics.shared.issues.count == before)
        } else {
            check("a missing file is just missing", false)
        }

        print(fails == 0 ? "\n  all persistence checks pass" : "\n  \(fails) FAILED")
    }
}
