import AVFoundation
import Foundation

/// One sound in a scene: a player node plus whichever looping strategy suits the file length.
final class LayerPlayer {
    let node = AVAudioPlayerNode()
    let layer: AudioLayer

    private let file: AVAudioFile
    private var looper: StreamingLooper?

    /// Above this, hold the file in memory and let the engine loop it; below it, stream.
    /// 60 s of 48 kHz stereo float is roughly 23 MB — acceptable per layer; a 10-minute track
    /// would be ten times that, which is not.
    private static let inMemoryLimitSeconds: Double = 60

    var duration: Double { Double(file.length) / file.processingFormat.sampleRate }
    var format: AVAudioFormat { file.processingFormat }

    init(layer: AudioLayer) throws {
        self.layer = layer
        self.file = try AVAudioFile(forReading: layer.url)
    }

    func attach(to engine: AVAudioEngine) {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        node.pan = Float(layer.pan)
    }

    /// Begin playback silently; the caller ramps `node.volume` up.
    func start() {
        node.volume = 0
        let startFrame = randomStartFrame()

        if !layer.loops {
            node.scheduleFile(file, at: nil)
        } else if duration <= Self.inMemoryLimitSeconds {
            scheduleInMemoryLoop(startingAt: startFrame)
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

    /// The engine's `.loops` option always restarts at frame 0, so a random start offset has to
    /// be baked in by rotating the buffer instead of seeking.
    private func scheduleInMemoryLoop(startingAt offset: AVAudioFramePosition) {
        guard let full = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: AVAudioFrameCount(file.length)) else { return }
        do { try file.read(into: full) } catch { return }

        let buffer = rotate(full, by: AVAudioFrameCount(offset)) ?? full
        node.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
    }

    /// `processingFormat` is always deinterleaved float32, so channels can be memcpy'd directly.
    private func rotate(_ buffer: AVAudioPCMBuffer, by offset: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        let n = buffer.frameLength
        guard offset > 0, offset < n,
              let src = buffer.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: n),
              let dst = out.floatChannelData
        else { return nil }

        let tail = Int(n - offset)
        let head = Int(offset)
        let size = MemoryLayout<Float>.size

        for ch in 0..<Int(buffer.format.channelCount) {
            memcpy(dst[ch], src[ch] + head, tail * size)
            memcpy(dst[ch] + tail, src[ch], head * size)
        }
        out.frameLength = n
        return out
    }
}
