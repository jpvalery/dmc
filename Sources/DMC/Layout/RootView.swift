import AppKit
import SwiftUI

struct RootView: View {
    var tabs: TabsModel
    var engine: SceneEngine
    var store: SceneStore
    @Bindable var router: UIRouter
    var campaigns: CampaignStore
    var notes: NotesStore
    var hotkeys: HotkeyManager
    var effects: EffectStore
    var library: SoundLibrary
    var templates: TemplateLibrary
    var combat: CombatTracker
    var cue: SceneCue
    var catalogue: TabletopCatalogue
    var downloader: TrackDownloader
    @Binding var railCollapsed: Bool
    @Binding var notesHidden: Bool
    @Binding var combatShown: Bool

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ThreePaneView(railCollapsed: railCollapsed, notesHidden: notesHidden) {
            SceneRail(engine: engine,
                      store: store,
                      collapsed: railCollapsed,
                      campaigns: campaigns,
                      router: router,
                      effects: effects,
                      library: library,
                      cue: cue,
                      onNew: router.newScene,
                      onEdit: router.edit,
                      onNewEffect: router.newEffect,
                      onEditEffect: router.edit,
                      onBrowse: { router.showTabletop = true })
        } web: {
            // A swap, not an overlay. The pages live in their tabs' controllers, so they are
            // still loaded when the browser comes back.
            if combatShown {
                CombatPane(combat: combat,
                           railCollapsed: $railCollapsed,
                           notesHidden: $notesHidden,
                           combatShown: $combatShown)
            } else {
                WebPane(tabs: tabs,
                        railCollapsed: $railCollapsed,
                        notesHidden: $notesHidden,
                        combatShown: $combatShown)
            }
        } notes: {
            NotesPane(notes: notes, store: store, effects: effects, onTrigger: run)
        }
        .frame(minWidth: 720, minHeight: 620)
        .background(SceneHotkeys(engine: engine, store: store))
        .overlay {
            if router.showPalette {
                CommandPalette(items: paletteItems) { router.showPalette = false }
            }
        }
        .sheet(item: $router.editing) { target in
            SceneEditor(scene: target.scene,
                        isNew: target.isNew,
                        library: library,
                        engine: engine,
                        onSave: { store.upsert($0) },
                        onDelete: { store.delete(target.scene) })
        }
        .sheet(isPresented: $router.showTabletop) {
            TabletopBrowser(catalogue: catalogue, downloader: downloader)
        }
        .sheet(item: $router.editingEffect) { target in
            EffectEditor(effect: target.effect,
                         isNew: target.isNew,
                         library: library,
                         engine: engine,
                         onSave: { effects.upsert($0) },
                         onDelete: { effects.delete(target.effect) })
        }
        .sheet(isPresented: $router.showNewCampaign) {
            CampaignNameSheet(title: "New campaign",
                              confirmLabel: "Create",
                              name: "") { campaigns.create(name: $0) }
        }
        .sheet(item: $router.renaming) { campaign in
            CampaignNameSheet(title: "Rename campaign",
                              confirmLabel: "Save",
                              name: campaign.name) { campaigns.rename(campaign.id, to: $0) }
        }
        .sheet(item: $router.deleting) { campaign in
            DeleteCampaignSheet(campaign: campaign) { campaigns.delete(campaign.id) }
        }
        .sheet(isPresented: $router.showPadImport) {
            PadImportView { scene in
                store.upsert(scene)
                router.edit(scene)
            }
        }
        .onChange(of: router.showHotkeys) { _, wanted in
            guard wanted else { return }
            openWindow(id: PadMapperWindow.id)
            router.showHotkeys = false
        }
        .onChange(of: router.showTemplates) { _, wanted in
            guard wanted else { return }
            openWindow(id: TemplateWindow.id)
            router.showTemplates = false
        }
        .onAppear {
            // New downloads are worthless until the local index sees them.
            downloader.onBatchFinished = { Task { await library.scan() } }

            hotkeys.onAction = { action in
                switch action {
                case .none:
                    break
                case .scene(let id):
                    if let scene = store.scenes.first(where: { $0.id == id }) { engine.toggle(scene) }
                case .sceneIndex(let position):
                    let i = position - 1
                    if store.scenes.indices.contains(i) { engine.toggle(store.scenes[i]) }
                case .stopAll:
                    engine.stopAll()
                case .volumeUp:
                    engine.nudgeVolume(0.04)
                case .volumeDown:
                    engine.nudgeVolume(-0.04)
                case .toggleMute:
                    engine.toggleMute()
                case .togglePlayPause:
                    engine.togglePlayPause()
                case .effectIndex(let position):
                    let i = position - 1
                    if effects.effects.indices.contains(i) { engine.fire(effects.effects[i]) }
                case .effect(let id):
                    if let effect = effects.effects.first(where: { $0.id == id }) { engine.fire(effect) }
                case .nextScene:
                    cue.step(by: 1, scenes: store.scenes, engine: engine)
                case .previousScene:
                    cue.step(by: -1, scenes: store.scenes, engine: engine)
                case .newScene:
                    router.newScene()
                }
            }
            hotkeys.register()

            // Everything that happens at the table is written into today's session note, if the
            // DM has not turned that off.
            engine.onSceneStarted = { scene in
                logEvent("Scene: \(scene.name)")
                prewarmNeighbours(of: scene)
            }
            combat.onEvent = { logEvent($0) }

            // Switching campaigns swaps scenes, notes, tabs and macropad bindings together.
            // Audio stops first: the scenes it is playing are about to be replaced.
            campaigns.onWillSwitch = {
                engine.stopAll()
                cue.cancel()
                tabs.persist()
                notes.saveNow()
            }
            campaigns.onDidSwitch = {
                store.reload()
                effects.reload()
                combat.reload()
                notes.reload()
                tabs.reloadForCampaign()
                hotkeys.reloadForCampaign()
            }
            // Capture the open pages on quit so a relaunch mid-session keeps the DM's place.
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { tabs.persist(); notes.saveNow() } }
        }
    }

    // MARK: - Actions

    private func logEvent(_ line: String) {
        guard UserDefaults.standard.object(forKey: "log.enabled") as? Bool ?? true else { return }
        notes.appendLog(line)
    }

    /// Decode the scenes either side of the one that just started, so stepping to them is instant.
    private func prewarmNeighbours(of scene: SoundScene) {
        guard let i = store.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        for j in [i - 1, i + 1] where store.scenes.indices.contains(j) {
            engine.prewarm(store.scenes[j])
        }
    }

    /// A click on a `[[scene:…]]` cue in the notes.
    private func run(_ trigger: NoteTrigger) {
        switch trigger {
        case .scene(let name):
            guard let i = NoteLinks.match(name, in: store.scenes.map(\.name)) else { return }
            let scene = store.scenes[i]
            if engine.activeSceneID != scene.id { engine.play(scene) }
        case .effect(let name):
            guard let i = NoteLinks.match(name, in: effects.effects.map(\.name)) else { return }
            engine.fire(effects.effects[i])
        case .stopAll:
            engine.stopAll()
        }
    }

    // MARK: - Command palette

    private var paletteItems: [PaletteItem] {
        var out: [PaletteItem] = []

        for (i, scene) in store.scenes.enumerated() {
            let state = engine.activeSceneID == scene.id ? "playing" : (i < 9 ? "⌘\(i + 1)" : "")
            out.append(PaletteItem(id: "scene.\(scene.id)", title: scene.name, subtitle: state,
                                   symbol: scene.symbol, group: "Scene") {
                if engine.activeSceneID != scene.id { engine.play(scene) }
            })
        }
        for effect in effects.effects {
            out.append(PaletteItem(id: "effect.\(effect.id)", title: effect.name, subtitle: "fire",
                                   symbol: effect.symbol, group: "Effect") { engine.fire(effect) })
        }
        for session in notes.sessions {
            out.append(PaletteItem(id: "note.\(session.id)", title: session.displayName,
                                   subtitle: "", symbol: "note.text", group: "Note") {
                notes.select(session)
                notesHidden = false
            })
        }
        for campaign in campaigns.sorted where campaign.id != campaigns.activeID {
            out.append(PaletteItem(id: "campaign.\(campaign.id)", title: campaign.name,
                                   subtitle: "switch", symbol: "books.vertical", group: "Campaign") {
                campaigns.activate(campaign.id)
            })
        }
        for combatant in combat.order where !combatant.isLair {
            let hp = combatant.hp.map { "\($0)\(combatant.maxHP.map { "/\($0)" } ?? "") HP" } ?? ""
            out.append(PaletteItem(id: "combatant.\(combatant.id)", title: combatant.name,
                                   subtitle: hp, symbol: combatant.isPlayer ? "person.fill" : "pawprint.fill",
                                   group: "Combatant") { combatShown = true })
        }

        func command(_ id: String, _ title: String, _ symbol: String, _ run: @escaping () -> Void) {
            out.append(PaletteItem(id: "cmd.\(id)", title: title, subtitle: "", symbol: symbol,
                                   group: "Command", run: run))
        }
        command("stop", "Stop all audio", "stop.fill") { engine.stopAll() }
        command("pause", engine.isPaused ? "Resume audio" : "Pause audio", "playpause.fill") {
            engine.togglePlayPause()
        }
        command("mute", engine.isMuted ? "Unmute" : "Mute", "speaker.slash.fill") { engine.toggleMute() }
        command("today", "Today's session note", "note.text") {
            notes.openToday()
            notesHidden = false
        }
        command("combat", combatShown ? "Show browser" : "Show combat tracker", "figure.fencing") {
            combatShown.toggle()
        }
        if combatShown {
            command("turn", combat.isRunning ? "Next turn" : "Start combat", "forward.fill") { combat.next() }
            command("roll", "Roll initiative for NPCs", "dice") { combat.rollNPCInitiative() }
            command("undo", "Undo combat change", "arrow.uturn.backward") { combat.undo() }
        }
        command("newscene", "New scene…", "plus") { router.newScene() }
        command("neweffect", "New effect…", "bolt.fill") { router.newEffect() }
        command("templates", "Scene templates…", "square.grid.2x2") { router.showTemplates = true }
        command("tabletop", "Browse Tabletop Audio…", "arrow.down.circle") { router.showTabletop = true }
        command("pad", "Macropad & hotkeys…", "square.grid.3x3") { router.showHotkeys = true }
        command("rail", railCollapsed ? "Expand scene rail" : "Collapse scene rail", "sidebar.left") {
            railCollapsed.toggle()
        }
        command("notes", notesHidden ? "Show notes" : "Hide notes", "sidebar.right") { notesHidden.toggle() }
        command("tab", "New browser tab", "plus.square.on.square") { tabs.newTab() }
        command("split", tabs.isSplit ? "Close split" : "Split browser side by side",
                "rectangle.split.2x1") { tabs.toggleSplit() }
        command("home", "D&D Beyond campaigns", "house") { tabs.selected?.controller.goHome() }
        return out
    }
}

/// ⌘1–⌘9 fire the first nine scenes, ⌘0 stops everything. Zero-sized buttons rather than a
/// global event monitor, so the shortcuts respect focus and don't fight text fields.
private struct SceneHotkeys: View {
    var engine: SceneEngine
    var store: SceneStore

    var body: some View {
        ZStack {
            ForEach(Array(store.scenes.prefix(9).enumerated()), id: \.element.id) { index, scene in
                Button("") { engine.toggle(scene) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Button("") { engine.stopAll() }
                .keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}

enum Home {
    static let fallback = "https://www.dndbeyond.com/my-campaigns"

    static func url() -> URL {
        let stored = UserDefaults.standard.string(forKey: "web.home") ?? fallback
        return URL(string: stored) ?? URL(string: fallback)!
    }
}
