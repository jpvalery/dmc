import AVFoundation
import Foundation

/// Gapless looping for files too long to hold in memory.
///
/// A 10-minute 48 kHz stereo track decoded into a single `AVAudioPCMBuffer` is roughly 230 MB,
/// so long ambiences cannot use the engine's built-in `.loops` option. Instead we keep a few
/// short buffers permanently queued on the player node and top the queue back up each time one
/// is consumed, wrapping to frame 0 at end of file. Memory stays near 1 MB per layer and the
/// player never runs dry, so the loop point is inaudible.
final class StreamingLooper {
    private let file: AVAudioFile
    private let node: AVAudioPlayerNode
    private let chunkFrames: AVAudioFrameCount
    private let queue: DispatchQueue
    private let maxInFlight = 3

    private var inFlight = 0
    private var running = false

    init(file: AVAudioFile, node: AVAudioPlayerNode, chunkSeconds: Double = 2.0) {
        self.file = file
        self.node = node
        self.chunkFrames = AVAudioFrameCount(max(4096, chunkSeconds * file.processingFormat.sampleRate))
        self.queue = DispatchQueue(label: "dmc.looper.\(UUID().uuidString.prefix(8))",
                                   qos: .userInitiated)
    }

    func start(fromFrame frame: AVAudioFramePosition) {
        queue.async { [self] in
            guard !running else { return }
            running = true
            file.framePosition = min(max(0, frame), max(0, file.length - 1))
            pump()
        }
    }

    func stop() {
        queue.async { [self] in running = false }
    }

    /// Must be called on `queue`.
    private func pump() {
        while running, inFlight < maxInFlight {
            guard let buffer = nextChunk() else { running = false; return }
            inFlight += 1
            // .dataConsumed fires once the buffer has been handed to the render thread, which
            // is the right moment to queue another — earlier callbacks would over-buffer.
            node.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    self.inFlight -= 1
                    self.pump()
                }
            }
        }
    }

    /// Read one chunk, wrapping to the start of the file at EOF.
    ///
    /// A short read means EOF landed mid-chunk; that tail is still scheduled, because chunks
    /// behind it are already queued. A zero-length read means EOF landed exactly on a chunk
    /// boundary, which must wrap and re-read rather than report failure — reporting failure
    /// there would stop the loop after one pass.
    /// Internal rather than private so the offline verification harness can drive the
    /// wrap-at-EOF path directly; it is the one piece of this class with real edge cases.
    func nextChunk() -> AVAudioPCMBuffer? {
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }

        if file.framePosition >= file.length { file.framePosition = 0 }
        do { try file.read(into: buffer, frameCount: chunkFrames) } catch { return nil }

        if buffer.frameLength == 0 {
            file.framePosition = 0
            do { try file.read(into: buffer, frameCount: chunkFrames) } catch { return nil }
            if buffer.frameLength == 0 { return nil }  // genuinely empty file
        }
        return buffer
    }
}
