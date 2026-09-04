import Combine
import Foundation

/// Downloads chosen ambiences into the vault, one at a time.
///
/// Sequential on purpose: these are ~14 MB each and come from one person's server, so there is
/// no reason to open a dozen connections at once. Attribution is written as tracks land, because
/// the CC BY-NC-ND licence requires it.
@MainActor
final class TrackDownloader: ObservableObject {
    @Published private(set) var pending: [TTATrack] = []
    @Published private(set) var active: TTATrack?
    @Published private(set) var completed = 0
    @Published private(set) var failures: [Int: String] = [:]

    /// Set by the owner so a finished batch refreshes the local index.
    var onBatchFinished: (() -> Void)?

    private var isRunning = false

    var isBusy: Bool { active != nil || !pending.isEmpty }
    var totalInBatch: Int { completed + pending.count + (active == nil ? 0 : 1) }

    func enqueue(_ tracks: [TTATrack]) {
        let fresh = tracks.filter { track in
            !track.isDownloaded
                && track.id != active?.id
                && !pending.contains(where: { $0.id == track.id })
        }
        guard !fresh.isEmpty else { return }
        pending.append(contentsOf: fresh)
        start()
    }

    func cancelPending() {
        pending.removeAll()
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        Task { await drain() }
    }

    private func drain() async {
        defer {
            isRunning = false
            active = nil
            onBatchFinished?()
        }

        try? FileManager.default.createDirectory(at: TabletopAudio.folder,
                                                 withIntermediateDirectories: true)

        while !pending.isEmpty {
            let track = pending.removeFirst()
            active = track
            do {
                try await download(track)
                appendAttribution(for: track)
                completed += 1
            } catch {
                failures[track.key] = error.localizedDescription
            }
            // A short breath between requests rather than hammering one small server.
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    private func download(_ track: TTATrack) async throws {
        guard let url = URL(string: track.link) else {
            throw URLError(.badURL)
        }
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tempURL)
            throw URLError(.badServerResponse)
        }
        let destination = track.localURL
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    /// The BY in CC BY-NC-ND is not optional, so credit is recorded next to the audio itself.
    private func appendAttribution(for track: TTATrack) {
        let file = TabletopAudio.attributionFile
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? """
        # Attribution

        Audio in this folder is from Tabletop Audio (https://tabletopaudio.com), created by
        Damian Kastbauer, and is licensed under Creative Commons
        Attribution-NonCommercial-NoDerivatives 4.0 International (CC BY-NC-ND 4.0).
        https://creativecommons.org/licenses/by-nc-nd/4.0/

        Downloaded for personal, non-commercial use.

        ## Tracks

        """
        let line = "- \(track.title) (#\(track.key)) — \(track.link)\n"
        guard !text.contains(line) else { return }
        text += line
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }
}
