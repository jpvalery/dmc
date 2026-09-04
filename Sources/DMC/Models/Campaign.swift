import Foundation

struct Campaign: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var created: Date = Date()
    var lastOpened: Date = Date()

    var directory: URL {
        Vault.campaignsRoot.appending(path: id.uuidString, directoryHint: .isDirectory)
    }
}

struct CampaignIndex: Codable {
    var campaigns: [Campaign]
    var activeID: UUID
}

/// Reads and writes `campaigns.json`, and performs the one-time move of a pre-campaign vault
/// into its first campaign.
///
/// Deliberately not `@MainActor`: `Vault.bootstrap()` runs from stored-property initialisers,
/// before any actor context is guaranteed.
enum CampaignArchive {
    static var indexFile: URL { Vault.root.appending(path: "campaigns.json") }

    static func load() -> CampaignIndex? {
        guard let data = try? Data(contentsOf: indexFile),
              let index = try? JSONDecoder().decode(CampaignIndex.self, from: data),
              !index.campaigns.isEmpty
        else { return nil }
        return index
    }

    static func save(_ index: CampaignIndex) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: indexFile, options: .atomic)
    }

    /// Returns the campaign that should be active, creating the first one if needed.
    ///
    /// Migration moves rather than copies, so there is exactly one copy of the scenes and notes
    /// and no chance of editing an orphan. Anything already migrated is left alone.
    static func bootstrap() -> UUID {
        if let index = load() { return index.activeID }

        let fm = FileManager.default
        let campaign = Campaign(name: "My Campaign")
        try? fm.createDirectory(at: campaign.directory, withIntermediateDirectories: true)

        // Scenes and notes from the flat pre-campaign vault.
        let legacyScenes = Vault.root.appending(path: "scenes.json")
        if fm.fileExists(atPath: legacyScenes.path) {
            try? fm.moveItem(at: legacyScenes, to: campaign.directory.appending(path: "scenes.json"))
        }
        let legacyNotes = Vault.root.appending(path: "notes", directoryHint: .isDirectory)
        if fm.fileExists(atPath: legacyNotes.path) {
            try? fm.moveItem(at: legacyNotes,
                             to: campaign.directory.appending(path: "notes", directoryHint: .isDirectory))
        }

        // Tabs and hotkeys were app-wide defaults; they belong to that first campaign now.
        let defaults = UserDefaults.standard
        if let tabs = defaults.stringArray(forKey: "web.openTabs"), !tabs.isEmpty,
           let data = try? JSONEncoder().encode(tabs) {
            try? data.write(to: campaign.directory.appending(path: "tabs.json"), options: .atomic)
        }
        if let hotkeys = defaults.data(forKey: "hotkeys.bindings") {
            try? hotkeys.write(to: campaign.directory.appending(path: "hotkeys.json"), options: .atomic)
        }
        defaults.removeObject(forKey: "web.openTabs")
        defaults.removeObject(forKey: "hotkeys.bindings")

        save(CampaignIndex(campaigns: [campaign], activeID: campaign.id))
        return campaign.id
    }
}

@MainActor
final class CampaignStore: ObservableObject {
    @Published private(set) var campaigns: [Campaign] = []
    @Published private(set) var activeID: UUID = UUID()

    /// Flush the outgoing campaign's state before the switch, then reload after it.
    var onWillSwitch: (() -> Void)?
    var onDidSwitch: (() -> Void)?

    init() {
        Vault.bootstrap()
        reload()
    }

    var active: Campaign? { campaigns.first { $0.id == activeID } }

    var sorted: [Campaign] {
        campaigns.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func reload() {
        guard let index = CampaignArchive.load() else { return }
        campaigns = index.campaigns
        activeID = index.activeID
        Vault.activeCampaignID = index.activeID
    }

    @discardableResult
    func create(name: String) -> Campaign {
        let campaign = Campaign(name: name)
        try? FileManager.default.createDirectory(at: campaign.directory,
                                                 withIntermediateDirectories: true)
        campaigns.append(campaign)
        persist()
        activate(campaign.id)
        return campaign
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = campaigns.firstIndex(where: { $0.id == id }) else { return }
        campaigns[i].name = name
        persist()
    }

    /// Removes a campaign from the index and deletes its folder. The shared audio library is
    /// untouched — only this campaign's scenes, notes, tabs and hotkeys go.
    func delete(_ id: UUID) {
        guard campaigns.count > 1, let campaign = campaigns.first(where: { $0.id == id }) else { return }
        campaigns.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: campaign.directory)
        if activeID == id, let next = campaigns.first {
            persist()
            activate(next.id)
        } else {
            persist()
        }
    }

    func activate(_ id: UUID) {
        guard id != activeID || Vault.activeCampaignID != id else { return }
        guard campaigns.contains(where: { $0.id == id }) else { return }

        onWillSwitch?()

        if let i = campaigns.firstIndex(where: { $0.id == id }) {
            campaigns[i].lastOpened = Date()
        }
        activeID = id
        Vault.activeCampaignID = id
        persist()

        onDidSwitch?()
    }

    private func persist() {
        CampaignArchive.save(CampaignIndex(campaigns: campaigns, activeID: activeID))
    }
}
