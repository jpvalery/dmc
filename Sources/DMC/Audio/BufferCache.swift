import AVFoundation
import Foundation

/// Decoded audio for the loops short enough to hold in memory, shared by every scene.
///
/// Decoding a minute of audio is real work. It used to happen on the main thread, inside the
/// call that started a scene, so every pad press and every click paid for it — and paid again
/// for a layer that two scenes had in common. Now it runs on a background task, a file decoded
/// once stays decoded, and `SceneEngine.prewarm` can do it ahead of the press.
///
/// A scene's players hold their own reference to the buffer they are looping, so evicting an
/// entry here never pulls audio out from under something that is playing; it only means the
/// next scene that wants the file decodes it again.
actor BufferCache {
    static let shared = BufferCache()

    /// Above this a file is streamed, not held. 60 s of 48 kHz stereo float is about 23 MB.
    static let inMemoryLimitSeconds: Double = 60

    private let byteLimit = 384 * 1024 * 1024

    private struct Entry {
        let buffer: AVAudioPCMBuffer
        let modified: Date?
        let bytes: Int
        var lastUsed: UInt64
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<AVAudioPCMBuffer?, Error>] = [:]
    private var clock: UInt64 = 0

    /// The decoded loop for `url`, or nil when the file is too long to hold and should be streamed.
    func buffer(for url: URL) async throws -> AVAudioPCMBuffer? {
        let key = url.path
        let modified = Self.modificationDate(of: url)

        if var hit = entries[key], hit.modified == modified {
            clock += 1
            hit.lastUsed = clock
            entries[key] = hit
            return hit.buffer
        }

        if let pending = inFlight[key] { return try await pending.value }

        let task = Task.detached(priority: .userInitiated) { try Self.decode(url) }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        guard let buffer = try await task.value else { return nil }
        clock += 1
        entries[key] = Entry(buffer: buffer, modified: modified,
                             bytes: Self.byteCount(of: buffer), lastUsed: clock)
        evictIfNeeded()
        return buffer
    }

    func removeAll() {
        entries = [:]
    }

    private func evictIfNeeded() {
        var total = entries.values.reduce(0) { $0 + $1.bytes }
        guard total > byteLimit else { return }
        for (key, entry) in entries.sorted(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            guard total > byteLimit else { break }
            entries[key] = nil
            total -= entry.bytes
        }
    }

    // MARK: Decoding

    /// Synchronous, so the offline verification harness — and `LayerPlayer`'s fallback when a
    /// buffer was not prepared — can use the same code the cache does.
    nonisolated static func decode(_ url: URL) throws -> AVAudioPCMBuffer? {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard rate > 0, Double(file.length) / rate <= inMemoryLimitSeconds else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length))
        else { throw CocoaError(.fileReadUnknown) }
        try file.read(into: buffer)
        return buffer
    }

    private nonisolated static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private nonisolated static func byteCount(of buffer: AVAudioPCMBuffer) -> Int {
        Int(buffer.frameLength) * Int(buffer.format.channelCount) * MemoryLayout<Float>.size
    }
}
