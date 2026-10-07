import AVFoundation
import Foundation
import Observation

/// Plays scenes: several looping stems mixed at independent gains, crossfading between scenes.
///
/// Per-stem gain lives on each player node; the master fader is the main mixer's output volume,
/// so pulling the master down never disturbs the balance inside a scene. Scene layers feed a
/// `bed` submixer on the way to the main mixer, which is what lets an effect pull the *scene*
/// down (ducking) without touching the effect itself or the master.
@MainActor
@Observable
final class SceneEngine {
    /// The scene that was asked for. It lights up at once, even while its audio is still being
    /// decoded in the background.
    private(set) var activeSceneID: SoundScene.ID?
    private(set) var problems: [String] = []
    var masterVolume: Double {
        didSet {
            engine.mainMixerNode.outputVolume = Float(masterVolume)
            UserDefaults.standard.set(masterVolume, forKey: Self.masterKey)
        }
    }

    /// How many copies of each effect are sounding. An effect can be fired again before the
    /// first has finished, so this is a count rather than a flag.
    private(set) var soundingEffects: [UUID: Int] = [:]

    /// Paused rather than stopped: the graph stays attached and every player keeps its position,
    /// so resuming picks up mid-loop instead of restarting the scene.
    private(set) var isPaused = false

    private(set) var previewing: String?

    /// Fires when a scene the user asked for has actually begun sounding — not for the quiet
    /// restarts that follow an edit or an audio-device change.
    @ObservationIgnored var onSceneStarted: ((SoundScene) -> Void)?

    @ObservationIgnored private static let masterKey = "audio.masterVolume"
    /// How long the audio engine stays warm after the last sound ends. Stopping it at once saves
    /// a little power, but the next effect then waits for the output device to wake — noticeable
    /// on any device, and worse over Bluetooth — and a door slam is exactly when you can't wait.
    @ObservationIgnored private static let idleGrace = Duration.seconds(45)

    @ObservationIgnored private let engine = AVAudioEngine()
    /// Every scene layer plays through this, so ducking has one fader to move.
    @ObservationIgnored private let bed = AVAudioMixerNode()
    @ObservationIgnored private let cache = BufferCache.shared

    @ObservationIgnored private var active: [LayerPlayer] = []
    @ObservationIgnored private var retiring: [ObjectIdentifier: LayerPlayer] = [:]
    /// Keyed by player so one layer's ramp can be cancelled without disturbing the others —
    /// needed when a gain slider moves while a fade is still in flight.
    @ObservationIgnored private var fades: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Repeating timers for the sporadic layers of the active scene.
    @ObservationIgnored private var sporadicTasks: [UUID: Task<Void, Never>] = [:]

    private struct OneShot {
        let node: AVAudioPlayerNode
        /// Groups the copies of one effect so a stop request can find all of them.
        let tag: UUID
        let duck: Double
    }
    /// Effect nodes currently sounding. Keyed by a token rather than the node's address: a
    /// completion handler can arrive after its node is gone, and an address can be reused by
    /// the next node, which the stale handler would then tear down.
    @ObservationIgnored private var oneShots: [UUID: OneShot] = [:]

    @ObservationIgnored private var activeScene: SoundScene?
    @ObservationIgnored private var configChangePending = false

    /// Bumped by every request to play or stop, so a decode that finishes late can tell it has
    /// been overtaken and discard itself.
    @ObservationIgnored private var playGeneration = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var idleStop: Task<Void, Never>?

    @ObservationIgnored private var duckTask: Task<Void, Never>?
    @ObservationIgnored private var duckTarget: Float = 1

    /// Level to come back to when unmuting; nil when not muted.
    @ObservationIgnored private var premuteVolume: Double?

    var isMuted: Bool { premuteVolume != nil }
    var isPlaying: Bool { activeSceneID != nil }
    var currentScene: SoundScene? { activeScene }

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.masterKey) as? Double
        masterVolume = stored ?? 0.8
        engine.mainMixerNode.outputVolume = Float(masterVolume)
        engine.attach(bed)
        engine.connect(bed, to: engine.mainMixerNode, format: nil)
        observeConfigurationChanges()
    }

    // MARK: - Volume

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
        playOneShot(url: effect.randomURL, gain: effect.gain, tag: effect.id,
                    label: effect.name, duck: effect.duck, bus: engine.mainMixerNode)
    }

    /// One node per firing, torn down on completion. `tag` groups nodes so a stop request can
    /// find every copy; sporadic scene layers pass their layer id, effects their effect id.
    private func playOneShot(url: URL, gain: Double, tag: UUID, label: String,
                             duck: Double, bus: AVAudioNode) {
        let node = AVAudioPlayerNode()
        var attached = false
        do {
            let file = try AVAudioFile(forReading: url)
            engine.attach(node)
            attached = true
            engine.connect(node, to: bus, format: file.processingFormat)
            try ensureRunningForEffect()
            node.volume = Float(gain)

            let token = UUID()
            oneShots[token] = OneShot(node: node, tag: tag, duck: duck)
            soundingEffects[tag, default: 0] += 1
            updateDuck()

            // The completion handler fires on an audio thread, so it captures only the token —
            // a UUID is Sendable, an AVAudioPlayerNode is not. The node is looked up again on
            // the main actor, where the dictionary is the source of truth.
            node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let entry = self.oneShots[token] else { return }
                    self.detach(token)
                    self.release(entry.tag)
                    self.stopEngineIfIdle()
                }
            }
            node.play()
        } catch {
            if attached { engine.detach(node) }
            Log.audio.error("could not play \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            problems.append("Could not play \(label) — \(error.localizedDescription)")
        }
    }

    private func detach(_ token: UUID) {
        guard let entry = oneShots.removeValue(forKey: token) else { return }
        entry.node.stop()
        engine.detach(entry.node)
        updateDuck()
    }

    func isSounding(_ id: UUID) -> Bool { (soundingEffects[id] ?? 0) > 0 }

    /// Cuts an effect short — every copy of it that is currently sounding.
    func stopEffect(_ id: UUID) {
        for (token, entry) in oneShots where entry.tag == id { detach(token) }
        soundingEffects[id] = nil
        stopEngineIfIdle()
    }

    func stopAllEffects() {
        for token in Array(oneShots.keys) { detach(token) }
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

    // MARK: - Ducking

    /// Moves the bed to wherever the loudest ducking effect currently sounding wants it. Quick
    /// to get out of the way, slow to come back — the way a sound engineer would ride it.
    private func updateDuck() {
        let depth = oneShots.values.map(\.duck).max() ?? 0
        let target = Float(1 - depth.clamped(0, 0.95))
        guard target != duckTarget else { return }
        duckTarget = target

        let bed = self.bed
        let from = bed.outputVolume
        let duration = target < from ? 0.12 : 0.9
        duckTask?.cancel()
        duckTask = Task { @MainActor in
            await FadeRamp.glide(duration: duration) { t in
                bed.outputVolume = from + (target - from) * t
            }
            if !Task.isCancelled { bed.outputVolume = target }
        }
    }

    // MARK: - Preview

    /// Auditioning a single file while building a scene. One shared tag, so starting a new
    /// preview replaces the last rather than piling them up.
    @ObservationIgnored private let previewTag = UUID()

    func preview(_ relativePath: String, gain: Double = 0.9) {
        if previewing == relativePath {
            stopPreview()
            return
        }
        stopPreview()
        previewing = relativePath
        playOneShot(url: Vault.audio.appending(path: relativePath), gain: gain,
                    tag: previewTag, label: relativePath, duck: 0, bus: engine.mainMixerNode)
    }

    func stopPreview() {
        stopEffect(previewTag)
        previewing = nil
    }

    // MARK: - Sporadic layers

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
                                     tag: layer.id,
                                     label: (layer.file as NSString).lastPathComponent,
                                     duck: 0, bus: self.bed)
                }
            }
        }
    }

    private func stopSporadicLayers() {
        for task in sporadicTasks.values { task.cancel() }
        sporadicTasks = [:]
    }

    // MARK: - Live editing

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

    // MARK: - Transport

    func toggle(_ scene: SoundScene) {
        if activeSceneID == scene.id { stopAll() } else { play(scene) }
    }

    /// Decode a scene's loops ahead of time, so starting it is instant. Used for the scene a
    /// knob is turning toward, and for the neighbours of whatever is playing.
    func prewarm(_ scene: SoundScene) {
        let urls = scene.layers
            .filter { $0.isBound && $0.loops && !$0.sporadic }
            .map(\.url)
        guard !urls.isEmpty else { return }
        let cache = self.cache
        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls { group.addTask { _ = try? await cache.buffer(for: url) } }
            }
        }
    }

    /// Starts `scene`, crossfading from whatever is playing.
    ///
    /// Returns at once. The audio is decoded off the main thread (or taken from the cache), and
    /// the crossfade begins when it is ready — the outgoing scene keeps playing until then, so
    /// a slow decode is a short wait rather than a gap of silence or a frozen window.
    func play(_ scene: SoundScene, fadeInOverride: Double? = nil) {
        problems = []
        playGeneration &+= 1
        let generation = playGeneration
        activeSceneID = scene.id

        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let (players, issues) = await self.prepare(scene)
            // Overtaken while decoding: neither the scene nor its complaints are wanted now.
            guard generation == self.playGeneration, !Task.isCancelled else { return }
            self.problems.append(contentsOf: issues)
            self.commit(scene, players: players, fadeInOverride: fadeInOverride)
            if fadeInOverride == nil { self.onSceneStarted?(scene) }
        }
    }

    /// Opens every layer's file and decodes the loops concurrently. What went wrong comes back
    /// with the players rather than being posted, so a request that has been overtaken by the
    /// time it finishes can drop its complaints along with itself.
    private func prepare(_ scene: SoundScene) async -> ([LayerPlayer], [String]) {
        var players: [LayerPlayer] = []
        var issues: [String] = []
        for layer in scene.layers where layer.isBound && !layer.sporadic {
            do {
                players.append(try LayerPlayer(layer: layer))
            } catch {
                issues.append(problemDescription(for: layer, error: error))
            }
        }

        let cache = self.cache
        let failed = await withTaskGroup(of: (Int, Error?).self) { group -> [(Int, Error)] in
            for (index, player) in players.enumerated() {
                group.addTask {
                    do { try await player.prepare(using: cache); return (index, nil) }
                    catch { return (index, error) }
                }
            }
            var out: [(Int, Error)] = []
            for await (index, error) in group { if let error { out.append((index, error)) } }
            return out
        }

        for (index, error) in failed.sorted(by: { $0.0 > $1.0 }) {
            issues.append(problemDescription(for: players[index].layer, error: error))
            players.remove(at: index)
        }
        return (players, issues)
    }

    private func commit(_ scene: SoundScene, players: [LayerPlayer], fadeInOverride: Double?) {
        // Retire the outgoing scene with *its* fade-out, overlapping the incoming fade-in so
        // the two equal-power curves sum to constant power.
        let fadeOut = activeScene?.fadeOut ?? 1.0
        retireAll(fade: fadeOut)

        startSporadicLayers(of: scene)

        let unbound = scene.layers.filter { !$0.isBound }
        if !unbound.isEmpty {
            problems.append("\(unbound.count) imported slot\(unbound.count == 1 ? "" : "s") "
                            + "still need a sound assigned.")
        }

        // A scene made only of sporadic layers has no looping players at all, and is still
        // perfectly valid — its timers are already running.
        guard !players.isEmpty || !sporadicTasks.isEmpty else {
            if scene.layers.isEmpty { problems.append("\(scene.name) has no sounds yet.") }
            stopSporadicLayers()
            activeScene = nil
            activeSceneID = nil
            stopEngineIfIdle()
            return
        }

        for player in players { player.attach(to: engine, bus: bed) }

        do {
            try ensureRunning()
        } catch {
            Log.audio.error("engine start failed: \(error.localizedDescription, privacy: .public)")
            problems.append("Could not start the audio engine: \(error.localizedDescription)")
            for player in players { player.teardown(engine: engine) }
            stopSporadicLayers()
            activeScene = nil
            activeSceneID = nil
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
        // Overtake any decode still in flight, or the scene would start after being stopped.
        playGeneration &+= 1
        loadTask?.cancel()
        stopSporadicLayers()
        stopAllEffects()
        retireAll(fade: activeScene?.fadeOut ?? 1.0)
        activeScene = nil
        activeSceneID = nil
    }

    // MARK: - Engine lifecycle

    private func ensureRunning() throws {
        isPaused = false
        idleStop?.cancel()
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    /// Starting the engine for an effect must not clear the paused flag — the bed stays paused
    /// because its own nodes are paused, independently of the engine.
    private func ensureRunningForEffect() throws {
        idleStop?.cancel()
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    private var isIdle: Bool {
        active.isEmpty && retiring.isEmpty && oneShots.isEmpty && sporadicTasks.isEmpty
    }

    /// Lets the engine go idle once nothing has played for a while, so the app does not hold the
    /// audio hardware awake all evening — but not the instant the last sound ends. See `idleGrace`.
    private func stopEngineIfIdle() {
        guard isIdle, engine.isRunning else { return }
        idleStop?.cancel()
        idleStop = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.idleGrace)
            guard !Task.isCancelled, let self, self.isIdle, self.engine.isRunning else { return }
            self.engine.stop()
            self.isPaused = false
        }
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
