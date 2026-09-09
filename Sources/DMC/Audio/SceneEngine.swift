import AVFoundation
import Combine
import Foundation

/// Plays scenes: several looping stems mixed at independent gains, crossfading between scenes.
///
/// Per-stem gain lives on each player node; the master fader is the main mixer's output volume,
/// so pulling the master down never disturbs the balance inside a scene.
@MainActor
final class SceneEngine: ObservableObject {
    @Published private(set) var activeSceneID: SoundScene.ID?
    @Published private(set) var problems: [String] = []
    @Published var masterVolume: Double {
        didSet {
            engine.mainMixerNode.outputVolume = Float(masterVolume)
            UserDefaults.standard.set(masterVolume, forKey: Self.masterKey)
        }
    }

    private static let masterKey = "audio.masterVolume"

    /// Level to come back to when unmuting; nil when not muted.
    private var premuteVolume: Double?

    var isMuted: Bool { premuteVolume != nil }

    /// Silences the ambience without stopping it, so a scene keeps its place and its fades.
    func toggleMute() {
        if let previous = premuteVolume {
            masterVolume = previous
            premuteVolume = nil
        } else {
            premuteVolume = masterVolume
            masterVolume = 0
        }
    }

    /// One encoder detent. Finer than a keyboard shortcut's step because a knob gives you many.
    func nudgeVolume(_ delta: Double) {
        premuteVolume = nil
        masterVolume = (masterVolume + delta).clamped(0, 1)
    }

    private let engine = AVAudioEngine()
    private var active: [LayerPlayer] = []
    private var retiring: [ObjectIdentifier: LayerPlayer] = [:]
    /// Keyed by player so one layer's ramp can be cancelled without disturbing the others —
    /// needed when a gain slider moves while a fade is still in flight.
    private var fades: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Repeating timers for the sporadic layers of the active scene.
    private var sporadicTasks: [UUID: Task<Void, Never>] = [:]

    /// Effect nodes currently sounding, keyed so each can remove itself when it finishes.
    /// The effect id rides along so a stop request can find every node it spawned.
    private var oneShots: [ObjectIdentifier: (node: AVAudioPlayerNode, effect: UUID)] = [:]

    /// How many copies of each effect are sounding. An effect can be fired again before the
    /// first has finished, so this is a count rather than a flag.
    @Published private(set) var soundingEffects: [UUID: Int] = [:]
    private var activeScene: SoundScene?
    private var configChangePending = false

    var isPlaying: Bool { activeSceneID != nil }

    /// Paused rather than stopped: the graph stays attached and every player keeps its position,
    /// so resuming picks up mid-loop instead of restarting the scene.
    @Published private(set) var isPaused = false

    /// Transport toggle for the scene bed. Does nothing when no scene is loaded — "play" here
    /// resumes what was paused rather than guessing which scene to start.
    ///
    /// Pauses the scene's player nodes rather than the engine, so the graph keeps running and a
    /// one-shot effect can still be fired over a paused bed.
    func togglePlayPause() {
        guard activeSceneID != nil else { return }
        isPaused.toggle()
        for player in active {
            if isPaused { player.node.pause() } else { player.node.play() }
        }
    }

    // MARK: - One-shot effects

    /// Overlays a single sound on whatever is already playing.
    ///
    /// Each firing gets its own node so effects stack — on the scene bed and on each other — and
    /// tears itself down on completion. Deliberately unaffected by `isPaused`: a paused bed is
    /// the moment you most want a door slam.
    func fire(_ effect: SoundEffect) {
        playOneShot(url: effect.randomURL, gain: effect.gain, tag: effect.id, label: effect.name)
    }

    /// One node per firing, torn down on completion. `tag` groups nodes so a stop request can
    /// find every copy; sporadic scene layers pass their layer id, effects their effect id.
    private func playOneShot(url: URL, gain: Double, tag: UUID, label: String) {
        do {
            let file = try AVAudioFile(forReading: url)
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            try ensureRunningForEffect()
            node.volume = Float(gain)

            let key = ObjectIdentifier(node)
            oneShots[key] = (node, tag)
            soundingEffects[tag, default: 0] += 1
            // The completion handler fires on an audio thread, so it captures only the key —
            // an ObjectIdentifier is Sendable, an AVAudioPlayerNode is not. The node is looked
            // up again on the main actor, where the dictionary is the source of truth.
            node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let entry = self.oneShots[key] else { return }
                    entry.node.stop()
                    self.engine.detach(entry.node)
                    self.oneShots[key] = nil
                    self.release(entry.effect)
                    self.stopEngineIfIdle()
                }
            }
            node.play()
        } catch {
            problems.append("Could not play \(label) — \(error.localizedDescription)")
        }
    }

    func isSounding(_ id: UUID) -> Bool { (soundingEffects[id] ?? 0) > 0 }

    // MARK: - Preview

    /// Auditioning a single file while building a scene. One shared tag, so starting a new
    /// preview replaces the last rather than piling them up.
    private let previewTag = UUID()
    @Published private(set) var previewing: String?

    func preview(_ relativePath: String, gain: Double = 0.9) {
        if previewing == relativePath {
            stopPreview()
            return
        }
        stopPreview()
        previewing = relativePath
        playOneShot(url: Vault.audio.appending(path: relativePath),
                    gain: gain, tag: previewTag, label: relativePath)
    }

    func stopPreview() {
        stopEffect(previewTag)
        previewing = nil
    }

    private func startSporadicLayers(of scene: SoundScene) {
        stopSporadicLayers()
        for layer in scene.layers where layer.sporadic && layer.isBound {
            let low = min(layer.minGap, layer.maxGap)
            let high = max(layer.minGap, layer.maxGap)
            sporadicTasks[layer.id] = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    // Wait first: firing the instant a scene starts would stack every sporadic
                    // layer on the downbeat, which is exactly the regularity being avoided.
                    let gap = Double.random(in: low...max(low, high))
                    try? await Task.sleep(for: .seconds(gap))
                    guard !Task.isCancelled, let self, !self.isPaused else { continue }
                    self.playOneShot(url: layer.randomVariantURL, gain: layer.gain,
                                     tag: layer.id, label: (layer.file as NSString).lastPathComponent)
                }
            }
        }
    }

    private func stopSporadicLayers() {
        for task in sporadicTasks.values { task.cancel() }
        sporadicTasks = [:]
    }

    /// Cuts an effect short — every copy of it that is currently sounding.
    func stopEffect(_ id: UUID) {
        for (key, entry) in oneShots where entry.effect == id {
            entry.node.stop()
            engine.detach(entry.node)
            oneShots[key] = nil
        }
        soundingEffects[id] = nil
        stopEngineIfIdle()
    }

    func stopAllEffects() {
        for (key, entry) in oneShots {
            entry.node.stop()
            engine.detach(entry.node)
            oneShots[key] = nil
        }
        soundingEffects = [:]
        stopEngineIfIdle()
    }

    private func release(_ id: UUID) {
        guard let count = soundingEffects[id] else { return }
        if count <= 1 {
            soundingEffects[id] = nil
            // A preview that ran to its end should stop looking like it is still playing.
            if id == previewTag { previewing = nil }
        } else {
            soundingEffects[id] = count - 1
        }
    }

    /// Starting the engine for an effect must not clear the paused flag — the bed stays paused
    /// because its own nodes are paused, independently of the engine.
    private func ensureRunningForEffect() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }
    var currentScene: SoundScene? { activeScene }

    func isLive(layer id: UUID) -> Bool { active.contains { $0.layer.id == id } }

    /// Apply a gain change to a layer that is already sounding, so the mix can be tuned by ear
    /// while the scene plays. Cancels that layer's in-flight ramp so the slider wins.
    func setLiveGain(_ gain: Double, forLayer id: UUID) {
        guard let player = active.first(where: { $0.layer.id == id }) else { return }
        fades[ObjectIdentifier(player)]?.cancel()
        fades[ObjectIdentifier(player)] = nil
        player.node.volume = Float(gain)
    }

    /// Re-apply an edited scene. Adding or removing layers cannot be patched into a running
    /// graph safely, so the scene restarts — briefly, and only when it is the one playing.
    func refreshIfPlaying(_ scene: SoundScene) {
        guard activeSceneID == scene.id else { return }
        play(scene, fadeInOverride: 0.3)
    }

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.masterKey) as? Double
        masterVolume = stored ?? 0.8
        engine.mainMixerNode.outputVolume = Float(masterVolume)
        observeConfigurationChanges()
    }

    // MARK: - Transport

    func toggle(_ scene: SoundScene) {
        if activeSceneID == scene.id { stopAll() } else { play(scene) }
    }

    func play(_ scene: SoundScene, fadeInOverride: Double? = nil) {
        problems = []

        // Retire the outgoing scene with *its* fade-out, overlapping the incoming fade-in so
        // the two equal-power curves sum to constant power.
        let fadeOut = activeScene?.fadeOut ?? 1.0
        retireAll(fade: fadeOut)

        startSporadicLayers(of: scene)

        var players: [LayerPlayer] = []
        let unbound = scene.layers.filter { !$0.isBound }
        if !unbound.isEmpty {
            problems.append("\(unbound.count) imported slot\(unbound.count == 1 ? "" : "s") "
                            + "still need a sound assigned.")
        }
        for layer in scene.layers where layer.isBound && !layer.sporadic {
            do {
                players.append(try LayerPlayer(layer: layer))
            } catch {
                problems.append(problemDescription(for: layer, error: error))
            }
        }

        // A scene made only of sporadic layers has no looping players at all, and is still
        // perfectly valid — its timers are already running.
        guard !players.isEmpty || !sporadicTasks.isEmpty else {
            if scene.layers.isEmpty { problems.append("\(scene.name) has no sounds yet.") }
            stopSporadicLayers()
            activeScene = nil
            activeSceneID = nil
            return
        }

        for player in players { player.attach(to: engine) }

        do {
            try ensureRunning()
        } catch {
            problems.append("Could not start the audio engine: \(error.localizedDescription)")
            for player in players { player.teardown(engine: engine) }
            return
        }

        activeScene = scene
        activeSceneID = scene.id
        active = players

        let fadeIn = fadeInOverride ?? scene.fadeIn
        for player in players {
            player.start()
            let target = Float(player.layer.gain)
            fades[ObjectIdentifier(player)] = Task { @MainActor in
                await FadeRamp.run(node: player.node, from: 0, to: target,
                                   curve: .rising, duration: fadeIn)
            }
        }
    }

    func stopAll() {
        stopSporadicLayers()
        stopAllEffects()
        retireAll(fade: activeScene?.fadeOut ?? 1.0)
        activeScene = nil
        activeSceneID = nil
    }

    // MARK: - Engine lifecycle

    private func ensureRunning() throws {
        isPaused = false
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    /// Fade a set of players out, then detach.
    ///
    /// Detaching happens **only** in the ramp's completion. Detaching a node that is still
    /// rendering is the classic crash in this design, so the players are moved off `active`
    /// into `retiring` and held there until their fade finishes.
    private func retireAll(fade: Double) {
        let outgoing = active
        active = []

        for player in outgoing {
            let key = ObjectIdentifier(player)
            retiring[key] = player
            let start = player.node.volume
            fades[key]?.cancel()
            fades[key] = Task { @MainActor in
                await FadeRamp.run(node: player.node, from: start, to: 0,
                                   curve: .falling, duration: fade)
                player.teardown(engine: self.engine)
                self.retiring[key] = nil
                self.fades[key] = nil
                self.stopEngineIfIdle()
            }
        }
        if outgoing.isEmpty { stopEngineIfIdle() }
    }

    /// Let the engine go idle when nothing is playing, so the app stops holding the audio
    /// hardware awake between scenes — it matters on battery.
    private func stopEngineIfIdle() {
        guard active.isEmpty, retiring.isEmpty, oneShots.isEmpty, engine.isRunning else { return }
        engine.stop()
        isPaused = false
    }

    /// Tear everything down immediately, no fades. Used when the graph is already invalid.
    private func hardStop() {
        for fade in fades.values { fade.cancel() }
        fades = [:]
        for player in active { player.teardown(engine: engine) }
        for player in retiring.values { player.teardown(engine: engine) }
        active = []
        retiring = [:]
        if engine.isRunning { engine.stop() }
    }

    // MARK: - Device changes

    /// Without this, plugging in a speaker or waking from sleep silently kills all audio
    /// mid-session: the engine stops and its output connections are invalidated, and nothing
    /// brings them back on its own. The graph cannot be patched in place, so it is rebuilt and
    /// the current scene resumed at its own gains.
    private func observeConfigurationChanges() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
    }

    /// The notification arrives in bursts when a device changes; coalesce them.
    private func scheduleRebuild() {
        guard !configChangePending else { return }
        configChangePending = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            configChangePending = false

            guard let scene = activeScene else {
                hardStop()
                return
            }
            hardStop()
            // Short fade in: fast enough to read as recovery, slow enough not to click.
            play(scene, fadeInOverride: 0.25)
        }
    }

    // MARK: - Diagnostics

    private func problemDescription(for layer: AudioLayer, error: Error) -> String {
        let ext = (layer.file as NSString).pathExtension.lowercased()
        if AudioFormats.knownUnplayable.contains(ext) {
            return "\(layer.file) — .\(ext) can't be decoded by macOS; convert to .m4a, .flac or .wav."
        }
        if !FileManager.default.fileExists(atPath: layer.url.path) {
            return "\(layer.file) — file is missing."
        }
        return "\(layer.file) — \(error.localizedDescription)"
    }
}
