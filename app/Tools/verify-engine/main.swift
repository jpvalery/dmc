import AVFoundation
import Foundation

// `clamped` lives with the pane layout in the app; the engine only needs the extension itself.
extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

/// The engine's scheduling, against a real `AVAudioEngine` with the master volume at zero so
/// nothing is audible: playing returns at once and decodes in the background, a request that is
/// overtaken never starts, effects tidy up after themselves, and a turning knob plays only the
/// scene it stops on.
@main
struct Probe {
    @MainActor
    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        let vault = CommandLine.arguments[1]
        UserDefaults.standard.set(vault, forKey: "vault.path")
        UserDefaults.standard.set(0.0, forKey: "audio.masterVolume")   // silent
        Vault.bootstrap()

        var fails = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("  \(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            if !ok { fails += 1 }
        }

        // Test tones, written once.
        func tone(_ name: String, seconds: Double, frequency: Double) throws {
            let url = Vault.audio.appending(path: name)
            guard !FileManager.default.fileExists(atPath: url.path) else { return }
            let rate = 48000.0
            let out = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            let frames = AVAudioFrameCount(seconds * rate)
            let buffer = AVAudioPCMBuffer(pcmFormat: out.processingFormat, frameCapacity: frames)!
            buffer.frameLength = frames
            for ch in 0..<2 {
                for i in 0..<Int(frames) {
                    buffer.floatChannelData![ch][i] = Float(0.4 * sin(2 * .pi * frequency * Double(i) / rate))
                }
            }
            try out.write(from: buffer)
        }
        try? FileManager.default.createDirectory(at: Vault.audio, withIntermediateDirectories: true)
        try? tone("loop.wav", seconds: 2, frequency: 220)
        try? tone("long.wav", seconds: 70, frequency: 110)
        try? tone("blip.wav", seconds: 0.3, frequency: 880)

        func scene(_ name: String, files: [String] = ["loop.wav"]) -> SoundScene {
            var s = SoundScene(name: name, layers: files.map { AudioLayer(file: $0, gain: 0.5) })
            s.fadeIn = 0.1
            s.fadeOut = 0.1
            return s
        }
        func waitUntil(_ seconds: Double = 4, _ condition: () -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .seconds(seconds)
            while ContinuousClock.now < deadline {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return condition()
        }

        let engine = SceneEngine()
        var started: [String] = []
        engine.onSceneStarted = { started.append($0.name) }

        // MARK: Playing returns at once, and the sound follows
        let tavern = scene("Tavern", files: ["loop.wav", "long.wav"])
        engine.play(tavern)
        check("the scene is marked active immediately", engine.activeSceneID == tavern.id)
        let live = await waitUntil { tavern.layers.allSatisfy { engine.isLive(layer: $0.id) } }
        check("both layers (in-memory and streamed) go live", live)
        check("the start is reported once", started == ["Tavern"], "\(started)")

        // MARK: Overtaken requests never start
        let crypt = scene("Crypt"), forest = scene("Forest")
        started = []
        engine.play(crypt)
        engine.play(forest)
        let forestLive = await waitUntil { engine.isLive(layer: forest.layers[0].id) }
        check("only the last of two quick requests starts", forestLive && !engine.isLive(layer: crypt.layers[0].id))
        check("and only it is reported", started == ["Forest"], "\(started)")
        check("the outgoing scene is retired", !tavern.layers.contains { engine.isLive(layer: $0.id) })

        // MARK: Stopping beats a decode still in flight
        let swamp = scene("Swamp", files: ["long.wav", "loop.wav"])
        started = []
        engine.play(swamp)
        engine.stopAll()
        try? await Task.sleep(for: .milliseconds(1200))
        check("a scene stopped before it was ready never starts",
              !swamp.layers.contains { engine.isLive(layer: $0.id) } && engine.activeSceneID == nil && started.isEmpty,
              "active=\(String(describing: engine.activeSceneID)) started=\(started)")

        // MARK: A missing file is reported and does not stop the rest
        let ruins = SoundScene(name: "Ruins", layers: [AudioLayer(file: "gone.wav"), AudioLayer(file: "loop.wav")])
        engine.play(ruins)
        let ruinsLive = await waitUntil { engine.isLive(layer: ruins.layers[1].id) }
        check("the playable layer still plays", ruinsLive)
        check("the missing one is reported", engine.problems.contains { $0.contains("gone.wav") },
              engine.problems.joined(separator: " | "))

        // MARK: Edits restart quietly
        started = []
        engine.refreshIfPlaying(ruins)
        try? await Task.sleep(for: .milliseconds(600))
        check("a refresh is not reported as a new scene", started.isEmpty, "\(started)")
        check("and the scene is still live", engine.isLive(layer: ruins.layers[1].id))
        engine.stopAll()

        // MARK: Effects tidy up
        let blip = SoundEffect(name: "Blip", file: "blip.wav", gain: 0.5)
        engine.fire(blip)
        engine.fire(blip)
        check("two firings count as two", engine.soundingEffects[blip.id] == 2, "\(engine.soundingEffects[blip.id] ?? 0)")
        let tidy = await waitUntil(3) { !engine.isSounding(blip.id) }
        check("they finish and are forgotten", tidy)
        engine.fire(blip)
        engine.stopEffect(blip.id)
        check("an effect can be cut short", !engine.isSounding(blip.id))
        var ducking = SoundEffect(name: "Boom", file: "blip.wav", gain: 0.5)
        ducking.duck = 0.5
        engine.fire(ducking)
        let duckDone = await waitUntil(3) { !engine.isSounding(ducking.id) }
        check("a ducking effect completes cleanly", duckDone)

        // MARK: The knob: many detents, one scene
        let rail = (1...6).map { scene("Scene \($0)") }
        let cue = SceneCue()
        started = []
        engine.stopAll()
        for _ in 0..<4 { cue.step(by: 1, scenes: rail, engine: engine) }
        check("the cue points at the fourth scene while the knob turns",
              cue.cuedID == rail[3].id, "\(String(describing: cue.cuedID))")
        check("nothing has played yet", engine.activeSceneID == nil && started.isEmpty)
        let landed = await waitUntil { engine.isLive(layer: rail[3].layers[0].id) }
        check("the scene the knob stopped on plays", landed)
        check("exactly one scene was started, not four", started == ["Scene 4"], "\(started)")
        check("the cue clears once it settles", cue.cuedID == nil)

        started = []
        cue.step(by: -1, scenes: rail, engine: engine)
        check("turning back starts from what is playing", cue.cuedID == rail[2].id)
        let back = await waitUntil { engine.isLive(layer: rail[2].layers[0].id) }
        check("and plays it", back && started == ["Scene 3"], "\(started)")

        cue.step(by: -1, scenes: rail, engine: engine); cue.step(by: -1, scenes: rail, engine: engine)
        cue.step(by: 1, scenes: rail, engine: engine); cue.step(by: 1, scenes: rail, engine: engine)
        try? await Task.sleep(for: .milliseconds(900))
        check("turning away and back plays nothing new", started == ["Scene 3"], "\(started)")

        engine.stopAll()
        let silent = SceneEngine()
        let blank = SceneCue()
        blank.step(by: 1, scenes: [], engine: silent)
        check("an empty rail is a no-op", blank.cuedID == nil)

        print(fails == 0 ? "\n  all engine checks pass" : "\n  \(fails) FAILED")
        exit(fails == 0 ? 0 : 1)
    }
}
