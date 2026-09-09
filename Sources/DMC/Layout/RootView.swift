import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var tabs: TabsModel
    @ObservedObject var engine: SceneEngine
    @ObservedObject var store: SceneStore
    @ObservedObject var router: UIRouter
    @ObservedObject var campaigns: CampaignStore
    @ObservedObject var notes: NotesStore
    @ObservedObject var hotkeys: HotkeyManager
    @ObservedObject var effects: EffectStore
    @ObservedObject var library: SoundLibrary
    @ObservedObject var templates: TemplateLibrary
    @Binding var railCollapsed: Bool
    @Binding var notesHidden: Bool

    @StateObject private var catalogue = TabletopCatalogue()
    @StateObject private var downloader = TrackDownloader()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ThreePaneView(railCollapsed: railCollapsed, notesHidden: notesHidden) {
            SceneRail(engine: engine,
                      store: store,
                      collapsed: railCollapsed,
                      campaigns: campaigns,
                      router: router,
                      effects: effects,
                      onNew: router.newScene,
                      onEdit: router.edit,
                      onNewEffect: router.newEffect,
                      onEditEffect: router.edit,
                      onBrowse: { router.showTabletop = true })
        } web: {
            WebPane(tabs: tabs,
                    railCollapsed: $railCollapsed,
                    notesHidden: $notesHidden)
        } notes: {
            NotesPane(notes: notes)
        }
        .frame(minWidth: 720, minHeight: 620)
        .background(SceneHotkeys(engine: engine, store: store))
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
                    stepScene(by: 1)
                case .previousScene:
                    stepScene(by: -1)
                case .newScene:
                    router.newScene()
                }
            }
            hotkeys.register()

            // Switching campaigns swaps scenes, notes, tabs and macropad bindings together.
            // Audio stops first: the scenes it is playing are about to be replaced.
            campaigns.onWillSwitch = {
                engine.stopAll()
                tabs.persist()
                notes.saveNow()
            }
            campaigns.onDidSwitch = {
                store.reload()
                effects.reload()
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

    /// Step through the rail, wrapping. With nothing playing, the first turn starts the rail
    /// rather than doing nothing — a knob that appears dead is worse than one that starts.
    private func stepScene(by offset: Int) {
        let scenes = store.scenes
        guard !scenes.isEmpty else { return }
        guard let activeID = engine.activeSceneID,
              let current = scenes.firstIndex(where: { $0.id == activeID })
        else {
            engine.play(scenes[offset > 0 ? 0 : scenes.count - 1])
            return
        }
        let next = (current + offset + scenes.count) % scenes.count
        engine.play(scenes[next])
    }
}

/// ⌘1–⌘9 fire the first nine scenes, ⌘0 stops everything. Zero-sized buttons rather than a
/// global event monitor, so the shortcuts respect focus and don't fight text fields.
private struct SceneHotkeys: View {
    @ObservedObject var engine: SceneEngine
    @ObservedObject var store: SceneStore

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
