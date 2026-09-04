import AppKit
import Foundation

/// Everything the app persists lives under one user-visible folder.
///
/// Two deliberate choices here:
///
/// 1. Not under `~/Documents`. Desktop, Documents and Downloads are TCC-protected, and an
///    ad-hoc-signed binary's designated requirement changes on every rebuild — so a Documents
///    vault would re-prompt for access after each `make`. The home directory root carries no
///    such protection.
/// 2. Not `~/DMC`. macOS volumes are case-insensitive by default, so `~/DMC` collides with a
///    checkout at `~/dmc` and the vault would scribble into its own source tree.
enum Vault {
    static let defaultFolderName = "DMConsole"

    static var root: URL {
        if let override = UserDefaults.standard.string(forKey: "vault.path"), !override.isEmpty {
            return URL(filePath: (override as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: defaultFolderName, directoryHint: .isDirectory)
    }

    // Shared across every campaign: the audio library is the expensive thing to build, and
    // duplicating it per campaign would mean re-downloading the same ambiences.
    static var audio: URL { root.appending(path: "audio", directoryHint: .isDirectory) }
    static var libraryFile: URL { root.appending(path: "library.json") }

    static var campaignsRoot: URL { root.appending(path: "campaigns", directoryHint: .isDirectory) }

    /// Set by `bootstrap()` and updated when the campaign changes. Every per-campaign path below
    /// resolves through it, so switching campaigns is a single assignment.
    static var activeCampaignID: UUID = UUID()

    static var campaignDir: URL {
        campaignsRoot.appending(path: activeCampaignID.uuidString, directoryHint: .isDirectory)
    }

    // Per-campaign.
    static var notes: URL { campaignDir.appending(path: "notes", directoryHint: .isDirectory) }
    static var scenesFile: URL { campaignDir.appending(path: "scenes.json") }
    static var effectsFile: URL { campaignDir.appending(path: "effects.json") }
    static var tabsFile: URL { campaignDir.appending(path: "tabs.json") }
    static var hotkeysFile: URL { campaignDir.appending(path: "hotkeys.json") }

    /// Lazily-once directory creation. A `static let` rather than a method call from
    /// `DMCApp.init`, because stored-property initializers run *before* an init body — so a
    /// `SceneStore()` property would otherwise scan the vault before it existed on first launch.
    private static let ready: Void = {
        for dir in [root, audio, campaignsRoot] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Adopts a pre-campaign vault on first run, moving its scenes and notes into a first
        // campaign rather than leaving them stranded at the root.
        activeCampaignID = CampaignArchive.bootstrap()
        try? FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    }()

    static func bootstrap() { _ = ready }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
