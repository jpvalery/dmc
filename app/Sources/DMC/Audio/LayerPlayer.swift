import AVFoundation
import Foundation

/// One sound in a scene: a player node plus whichever looping strategy suits the file length.
final class LayerPlayer {
    let node = AVAudioPlayerNode()
    let layer: AudioLayer

    private let file: AVAudioFile
    private var looper: StreamingLooper?
    /// The decoded loop, for files short enough to hold. Filled by `prepare`.
    private var memory: AVAudioPCMBuffer?

    var duration: Double { Double(file.length) / file.processingFormat.sampleRate }
    var format: AVAudioFormat { file.processingFormat }

    /// Short files are held in memory and looped by the engine; long ones are streamed.
    var holdsInMemory: Bool { layer.loops && duration <= BufferCache.inMemoryLimitSeconds }

    init(layer: AudioLayer) throws {
        self.layer = layer
        self.file = try AVAudioFile(forReading: layer.url)
    }

    /// Gets the decoded loop ready without blocking the caller. Streamed and one-shot layers
    /// have nothing to prepare.
    func prepare(using cache: BufferCache) async throws {
        guard holdsInMemory, memory == nil else { return }
        memory = try await cache.buffer(for: layer.url)
    }

    func attach(to engine: AVAudioEngine, bus: AVAudioNode? = nil) {
        engine.attach(node)
        engine.connect(node, to: bus ?? engine.mainMixerNode, format: format)
        node.pan = Float(layer.pan)
    }

    /// Begin playback silently; the caller ramps `node.volume` up.
    func start() {
        node.volume = 0
        let startFrame = randomStartFrame()

        if !layer.loops {
            node.scheduleFile(file, at: nil)
        } else if holdsInMemory {
            // `prepare` normally did this already; decoding here is the fallback for callers
            // that skipped it.
            if memory == nil { memory = try? BufferCache.decode(layer.url) }
            if let memory { scheduleInMemoryLoop(memory, startingAt: startFrame) }
        } else {
            let looper = StreamingLooper(file: file, node: node)
            self.looper = looper
            looper.start(fromFrame: startFrame)
        }
        node.play()
    }

    func teardown(engine: AVAudioEngine) {
        looper?.stop()
        looper = nil
        node.stop()
        engine.detach(node)
    }

    private func randomStartFrame() -> AVAudioFramePosition {
        guard layer.loops, layer.randomStart, file.length > 0 else { return 0 }
        return AVAudioFramePosition.random(in: 0..<file.length)
    }

    /// The engine's `.loops` option always restarts at frame 0, so a random start offset cannot
    /// be passed to it. Instead the rest of the file from that offset is queued to play once,
    /// and the whole buffer is queued behind it to loop — the player node plays its queue in
    /// order, so the join is gapless. That costs one copy of the *tail*, which is freed once it
    /// has played, where rotating the buffer cost a second full copy kept for as long as the
    /// layer loops.
    private func scheduleInMemoryLoop(_ full: AVAudioPCMBuffer, startingAt offset: AVAudioFramePosition) {
        if offset > 0, let lead = Self.slice(full, from: AVAudioFrameCount(offset)) {
            node.scheduleBuffer(lead, at: nil, options: [], completionHandler: nil)
        }
        node.scheduleBuffer(full, at: nil, options: .loops, completionHandler: nil)
    }

    /// Frames `offset..<frameLength` as a new buffer. `processingFormat` is always deinterleaved
    /// float32, so channels can be memcpy'd directly. Internal so the verification harness can
    /// exercise it.
    static func slice(_ buffer: AVAudioPCMBuffer, from offset: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let n = buffer.frameLength
        guard offset > 0, offset < n,
              let src = buffer.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: n - offset),
              let dst = out.floatChannelData
        else { return nil }

        let count = Int(n - offset)
        for ch in 0..<Int(buffer.format.channelCount) {
            memcpy(dst[ch], src[ch] + Int(offset), count * MemoryLayout<Float>.size)
        }
        out.frameLength = n - offset
        return out
    }
}
