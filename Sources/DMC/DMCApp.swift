import SwiftUI

@main
struct DMCApp: App {
    @StateObject private var tabs = TabsModel()
    @StateObject private var engine = SceneEngine()
    @StateObject private var store = SceneStore()
    @StateObject private var router = UIRouter()
    @StateObject private var campaigns = CampaignStore()

    @AppStorage("pane.railCollapsed") private var railCollapsed = false
    @AppStorage("pane.notesHidden") private var notesHidden = false

    private var web: WebController? { tabs.selected?.controller }

    var body: some Scene {
        WindowGroup("DMC") {
            RootView(tabs: tabs,
                     engine: engine,
                     store: store,
                     router: router,
                     campaigns: campaigns,
                     railCollapsed: $railCollapsed,
                     notesHidden: $notesHidden)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { tabs.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") { tabs.closeSelected() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(tabs.tabs.count < 2)
                Divider()
                Button("New Scene…") { router.newScene() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Browse Tabletop Audio…") { router.showTabletop = true }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Import SoundPad JSON…") { router.showPadImport = true }
                Divider()
                Button("New Campaign…") { router.showNewCampaign = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            // ⌘\ is deliberately left unbound so 1Password's Universal Autofill hotkey reaches
            // the focused field instead of being swallowed by the app.
            CommandGroup(after: .sidebar) {
                Button(railCollapsed ? "Expand Scene Rail" : "Collapse Scene Rail") {
                    railCollapsed.toggle()
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button(notesHidden ? "Show Notes" : "Hide Notes") { notesHidden.toggle() }
                    .keyboardShortcut("2", modifiers: [.command, .option])

                Divider()

                Button(tabs.isSplit ? "Close Split" : "Split Side by Side") { tabs.toggleSplit() }
                    .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Next Tab") { tabs.cycle(by: 1) }
                    .keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab") { tabs.cycle(by: -1) }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Divider()

                Button("Back") { web?.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!(web?.canGoBack ?? false))
                Button("Forward") { web?.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!(web?.canGoForward ?? false))
                Button("Reload") { web?.reloadOrStop() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Campaigns") { web?.goHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Open in Default Browser") { web?.openInDefaultBrowser() }

                Divider()

                Button(engine.isPaused ? "Resume Audio" : "Pause Audio") { engine.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [.command, .shift])
                    .disabled(!engine.isPlaying)
                Button("Stop All Audio") { engine.stopAll() }
                    .disabled(!engine.isPlaying)
                Button("Macropad & Hotkeys…") { router.showHotkeys = true }

                Menu("Switch Campaign") {
                    ForEach(campaigns.sorted) { campaign in
                        Button(campaign.name) { campaigns.activate(campaign.id) }
                            .disabled(campaign.id == campaigns.activeID)
                    }
                }
                Button("Import Folders as Scenes") { store.importFolders() }
                Button("Reload Scenes") { store.reload() }
                Button("Reveal Vault in Finder") { Vault.reveal(Vault.root) }
            }
        }
    }
}
