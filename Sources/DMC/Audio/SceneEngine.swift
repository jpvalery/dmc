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
    private var activeScene: SoundScene?
    private var configChangePending = false

    var isPlaying: Bool { activeSceneID != nil }
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

        var players: [LayerPlayer] = []
        let unbound = scene.layers.filter { !$0.isBound }
        if !unbound.isEmpty {
            problems.append("\(unbound.count) imported slot\(unbound.count == 1 ? "" : "s") "
                            + "still need a sound assigned.")
        }
        for layer in scene.layers where layer.isBound {
            do {
                players.append(try LayerPlayer(layer: layer))
            } catch {
                problems.append(problemDescription(for: layer, error: error))
            }
        }

        guard !players.isEmpty else {
            if scene.layers.isEmpty { problems.append("\(scene.name) has no sounds yet.") }
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
        retireAll(fade: activeScene?.fadeOut ?? 1.0)
        activeScene = nil
        activeSceneID = nil
    }

    // MARK: - Engine lifecycle

    private func ensureRunning() throws {
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
        guard active.isEmpty, retiring.isEmpty, engine.isRunning else { return }
        engine.stop()
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
