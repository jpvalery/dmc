import Foundation
import Observation

/// Steps through the rail without playing every scene the knob passes.
///
/// A rotary encoder sends one event per detent. Playing on each of them meant five clicks past
/// the scene you wanted built, faded in and faded out five scenes. Instead each detent only moves
/// a *cue* — shown in the rail — and the scene that is cued when the knob stops is the one that
/// plays. Its audio is decoded in the background as soon as it is cued, so it starts the moment
/// the knob settles.
@MainActor
@Observable
final class SceneCue {
    /// The scene the knob is currently pointing at, while it is still turning.
    private(set) var cuedID: SoundScene.ID?

    @ObservationIgnored private var settle: Task<Void, Never>?
    @ObservationIgnored private static let settleDelay = Duration.milliseconds(450)

    /// Moves the cue one scene along, wrapping. With nothing playing, the first turn starts from
    /// the top (or bottom) of the rail rather than doing nothing — a knob that appears dead is
    /// worse than one that starts.
    func step(by offset: Int, scenes: [SoundScene], engine: SceneEngine) {
        guard !scenes.isEmpty else { return }

        let from = cuedID ?? engine.activeSceneID
        let next: Int
        if let from, let current = scenes.firstIndex(where: { $0.id == from }) {
            next = (current + offset + scenes.count) % scenes.count
        } else {
            next = offset > 0 ? 0 : scenes.count - 1
        }

        let target = scenes[next]
        cuedID = target.id
        engine.prewarm(target)

        settle?.cancel()
        settle = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            self.cuedID = nil
            if engine.activeSceneID != target.id { engine.play(target) }
        }
    }

    func cancel() {
        settle?.cancel()
        cuedID = nil
    }
}
