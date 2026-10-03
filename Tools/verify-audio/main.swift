import AVFoundation
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
    if !ok { failures += 1 }
}

// Point the vault at the scratchpad; AudioLayer.url then resolves to the generated files.
UserDefaults.standard.set(CommandLine.arguments[1], forKey: "vault.path")
let audioDir = Vault.audio
let shortA = audioDir.appending(path: "short_a.wav")
let longFile = audioDir.appending(path: "long.wav")

// Two sines that do not share a period with the file, so a loop that starts at the wrong place
// cannot pass by accident. Written once into the scratch vault.
func writeTone(_ url: URL, seconds: Double, frequency: Double) throws {
    let rate = 48000.0
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
    ]
    let out = try AVAudioFile(forWriting: url, settings: settings)
    let frames = AVAudioFrameCount(seconds * rate)
    let buffer = AVAudioPCMBuffer(pcmFormat: out.processingFormat, frameCapacity: frames)!
    buffer.frameLength = frames
    for ch in 0..<2 {
        let data = buffer.floatChannelData![ch]
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            data[i] = Float(0.5 * sin(2 * .pi * frequency * t) + 0.2 * sin(2 * .pi * 331 * t))
        }
    }
    try out.write(from: buffer)
}
try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
if !FileManager.default.fileExists(atPath: shortA.path) { try writeTone(shortA, seconds: 3, frequency: 220) }
if !FileManager.default.fileExists(atPath: longFile.path) { try writeTone(longFile, seconds: 70, frequency: 110) }

// ------------------------------------------- 1. random start: lead-in, then the loop
// A random start used to rotate the buffer. Now the tail from the offset is queued to play once
// and the whole buffer is queued behind it to loop. What comes out must be the file, read from
// the offset and wrapping — sample for sample, across the join and across the wrap.
do {
    let file = try AVAudioFile(forReading: shortA)
    let fmt = file.processingFormat
    let full = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: full)
    let n = Int(full.frameLength)
    let offset = 12345

    let lead = LayerPlayer.slice(full, from: AVAudioFrameCount(offset))
    check("slice has the tail's length", lead.map { Int($0.frameLength) } == n - offset)
    check("slice starts at the offset",
          lead.map { $0.floatChannelData![0][0] == full.floatChannelData![0][offset] } ?? false)
    check("slice ends where the file ends",
          lead.map { $0.floatChannelData![0][n - offset - 1] == full.floatChannelData![0][n - 1] } ?? false)

    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: fmt)
    let renderFormat = AVAudioFormat(standardFormatWithSampleRate: fmt.sampleRate, channels: 2)!
    try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)

    node.scheduleBuffer(lead!, at: nil, options: [], completionHandler: nil)
    node.scheduleBuffer(full, at: nil, options: .loops, completionHandler: nil)
    node.volume = 1
    try engine.start()
    node.play()

    // Two and a bit passes: through the lead-in, over the join, and across the wrap.
    let total = n * 2 + 5000
    var out: [Float] = []
    out.reserveCapacity(total)
    let scratch = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: 4096)!
    while out.count < total {
        let status = try engine.renderOffline(AVAudioFrameCount(min(4096, total - out.count)), to: scratch)
        guard status == .success else { break }
        let ch = scratch.floatChannelData![0]
        out.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(scratch.frameLength)))
    }
    engine.stop()

    // The player may start a render block or two late; align on the first non-silent sample.
    let start = out.firstIndex { abs($0) > 1e-4 } ?? 0
    let source = full.floatChannelData![0]
    var wrong = 0
    var checked = 0
    for k in 0..<(total - start - 2048) {
        let expected = source[(offset + k) % n]
        if abs(out[start + k] - expected) > 2e-3 { wrong += 1 }
        checked += 1
    }
    check("lead-in + loop reproduces the file from the offset, wrapping gaplessly", wrong == 0 && checked > n,
          "\(wrong) of \(checked) samples differ")
}

// ------------------------------------------------- 2. streaming looper wraps past EOF
// The bug class here: stopping after one pass through a long file.
do {
    let file = try AVAudioFile(forReading: longFile)
    let node = AVAudioPlayerNode()
    let looper = StreamingLooper(file: file, node: node, chunkSeconds: 2.0)
    let fileFrames = file.length

    var produced: AVAudioFramePosition = 0
    var nilCount = 0
    // Ask for ~3x the file length; a correct looper never runs out.
    let target = fileFrames * 3
    var calls = 0
    while produced < target, calls < 5000 {
        calls += 1
        if let buf = looper.nextChunk() { produced += AVAudioFramePosition(buf.frameLength) }
        else { nilCount += 1; break }
    }
    check("looper never returns nil", nilCount == 0)
    check("looper produces >3x the file length", produced >= target,
          "\(produced) frames vs file \(fileFrames) (\(String(format: "%.1f", Double(produced)/Double(fileFrames)))x)")
}

// ----------------------------------------------- 3. in-memory loop renders gapless audio
// Offline manual rendering: exact, deterministic, and faster than realtime.
do {
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    let file = try AVAudioFile(forReading: shortA)
    let fmt = file.processingFormat

    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: fmt)

    let renderFormat = AVAudioFormat(standardFormatWithSampleRate: fmt.sampleRate, channels: 2)!
    try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)

    let full = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: full)
    node.scheduleBuffer(full, at: nil, options: .loops, completionHandler: nil)
    node.volume = 1.0

    try engine.start()
    node.play()

    let seconds = 12.0   // four passes through a 3s loop
    let totalFrames = AVAudioFrameCount(seconds * renderFormat.sampleRate)
    let scratch = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: 4096)!

    // RMS per 50ms window; a gap at a loop point shows up as a near-silent window.
    var windowRMS: [Float] = []
    var acc: Float = 0, accCount = 0
    let windowFrames = Int(0.05 * renderFormat.sampleRate)
    var rendered: AVAudioFrameCount = 0

    while rendered < totalFrames {
        let want = min(4096, totalFrames - rendered)
        let status = try engine.renderOffline(want, to: scratch)
        guard status == .success else { break }
        let ch = scratch.floatChannelData![0]
        for i in 0..<Int(scratch.frameLength) {
            acc += ch[i] * ch[i]; accCount += 1
            if accCount == windowFrames { windowRMS.append(sqrt(acc / Float(accCount))); acc = 0; accCount = 0 }
        }
        rendered += scratch.frameLength
    }
    engine.stop()

    let quiet = windowRMS.filter { $0 < 0.05 }.count
    check("offline render produced audio", windowRMS.count > 200, "\(windowRMS.count) windows")
    check("no dropouts across 4 loop passes", quiet == 0,
          "\(quiet)/\(windowRMS.count) near-silent 50ms windows")
    let minR = windowRMS.min() ?? 0, maxR = windowRMS.max() ?? 0
    check("loop level is steady", minR > 0.2 && maxR < 0.45,
          String(format: "rms %.3f…%.3f", minR, maxR))
}

// -------------------------------------------------- 4. equal-power crossfade stays flat
// Linear ramps dip ~3dB mid-crossfade; the sin/cos pair must not.
do {
    var worst: Float = 0
    for i in 0...100 {
        let t = Float(i) / 100
        let rising = sin(t * .pi / 2)
        let falling = cos(t * .pi / 2)
        let power = rising * rising + falling * falling
        worst = max(worst, abs(power - 1))
    }
    check("crossfade holds constant power", worst < 0.001,
          String(format: "worst deviation %.5f", worst))

    var linearWorst: Float = 0
    for i in 0...100 {
        let t = Float(i) / 100
        let power = t * t + (1 - t) * (1 - t)
        linearWorst = max(linearWorst, abs(power - 1))
    }
    check("linear would have dipped (control)", linearWorst > 0.4,
          String(format: "linear deviates %.2f (=%.1f dB dip)", linearWorst, 10 * log10(1 - linearWorst)))
}

// ------------------------------------- 5. rapid attach/detach under a running engine
// Exercises the detach-on-completion path that crashes if a node is detached mid-render.
do {
    let engine = AVAudioEngine()
    let renderFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    _ = engine.mainMixerNode
    try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)
    try engine.start()
    let scratch = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: 4096)!

    var survived = 0
    for _ in 0..<60 {
        let layer = AudioLayer(file: "short_a.wav")
        let player = try LayerPlayer(layer: layer)
        player.attach(to: engine)
        player.start()
        player.node.volume = 0.5
        _ = try engine.renderOffline(1024, to: scratch)
        player.teardown(engine: engine)
        _ = try engine.renderOffline(1024, to: scratch)
        survived += 1
    }
    engine.stop()
    check("60 attach/play/detach cycles under render", survived == 60, "\(survived)/60")
}

// -------------------------------------------------- 6. the buffer cache
do {
    let cache = BufferCache()
    let first = try await cache.buffer(for: shortA)
    let second = try await cache.buffer(for: shortA)
    check("a short loop is decoded", first != nil && first!.frameLength > 0)
    check("the second request is the cached buffer", first != nil && first === second)

    let direct = try BufferCache.decode(shortA)
    check("synchronous decode matches", direct?.frameLength == first?.frameLength)

    let longLength = try AVAudioFile(forReading: longFile).length
    let seconds = Double(longLength) / 48000
    let long = try await cache.buffer(for: longFile)
    check("a file over the limit is left to stream", seconds > BufferCache.inMemoryLimitSeconds && long == nil,
          String(format: "%.0f s", seconds))

    // Concurrent requests for one file share a single decode.
    let burst = try await withThrowingTaskGroup(of: AVAudioPCMBuffer?.self) { group -> [AVAudioPCMBuffer?] in
        let fresh = BufferCache()
        for _ in 0..<6 { group.addTask { try await fresh.buffer(for: shortA) } }
        var all: [AVAudioPCMBuffer?] = []
        for try await buffer in group { all.append(buffer) }
        return all
    }
    check("concurrent requests agree", burst.allSatisfy { $0 != nil && $0!.frameLength == first!.frameLength })
}

// ------------------------------------------------------- 7. fades follow the clock
// Counting 60 Hz steps made a fade run long, because every sleep overshoots a little.
do {
    let node = AVAudioPlayerNode()
    let duration = 1.0
    let clock = ContinuousClock()
    let began = clock.now
    await FadeRamp.run(node: node, from: 0, to: 1, curve: .rising, duration: duration)
    let took = Double((clock.now - began).components.seconds)
        + Double((clock.now - began).components.attoseconds) / 1e18
    check("a 1.0 s fade takes 1.0 s", abs(took - duration) < 0.06, String(format: "%.3f s", took))
    check("and ends at its target", node.volume == 1)
}

// ------------------------------------------------------------- 8. the bed fader ducks the scene
do {
    let engine = AVAudioEngine()
    let bed = AVAudioMixerNode()
    let node = AVAudioPlayerNode()
    let file = try AVAudioFile(forReading: shortA)
    let fmt = file.processingFormat
    engine.attach(bed)
    engine.attach(node)
    engine.connect(node, to: bed, format: fmt)
    engine.connect(bed, to: engine.mainMixerNode, format: nil)
    let renderFormat = AVAudioFormat(standardFormatWithSampleRate: fmt.sampleRate, channels: 2)!
    try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)

    let full = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: full)
    node.scheduleBuffer(full, at: nil, options: .loops, completionHandler: nil)
    try engine.start()
    node.play()

    func rms(frames: Int) throws -> Float {
        let scratch = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: 4096)!
        var acc: Float = 0, count = 0
        while count < frames {
            _ = try engine.renderOffline(4096, to: scratch)
            let ch = scratch.floatChannelData![0]
            for i in 0..<Int(scratch.frameLength) { acc += ch[i] * ch[i] }
            count += Int(scratch.frameLength)
        }
        return sqrt(acc / Float(count))
    }

    bed.outputVolume = 1
    _ = try rms(frames: 8192)                 // settle
    let open = try rms(frames: 48000)
    bed.outputVolume = 0.5
    _ = try rms(frames: 8192)
    let ducked = try rms(frames: 48000)
    engine.stop()
    check("ducking the bed halves the scene's level", abs(ducked / open - 0.5) < 0.05,
          String(format: "%.3f → %.3f (ratio %.2f)", open, ducked, ducked / open))
}

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
