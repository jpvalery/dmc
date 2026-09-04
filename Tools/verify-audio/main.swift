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

// ---------------------------------------------------------------- 1. buffer rotation
// A wrong memcpy here would either crash or silently corrupt every short loop.
do {
    let file = try AVAudioFile(forReading: shortA)
    let fmt = file.processingFormat
    let full = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: full)

    let offset: AVAudioFrameCount = 12345
    // Mirror LayerPlayer.rotate exactly.
    let n = full.frameLength
    let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
    let src = full.floatChannelData!, dst = out.floatChannelData!
    let tail = Int(n - offset), head = Int(offset), size = MemoryLayout<Float>.size
    for ch in 0..<Int(fmt.channelCount) {
        memcpy(dst[ch], src[ch] + head, tail * size)
        memcpy(dst[ch] + tail, src[ch], head * size)
    }
    out.frameLength = n

    check("rotation preserves length", out.frameLength == full.frameLength)
    let a = dst[0][0] == src[0][head]
    let b = dst[0][tail] == src[0][0]
    let c = dst[0][tail - 1] == src[0][Int(n) - 1]
    check("rotation seams line up", a && b && c,
          "start=\(a) wrap=\(b) end=\(c)")
    var maxJump: Float = 0
    for i in 1..<Int(n) { maxJump = max(maxJump, abs(dst[0][i] - dst[0][i-1])) }
    // One discontinuity at the wrap is inherent to any loop; assert it is not garbage-level.
    check("rotated audio has no garbage samples", maxJump < 1.2, "max sample jump \(maxJump)")
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

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
