import AVFoundation
import Foundation

/// Volume ramps shaped for ambience.
///
/// Linear ramps are audibly wrong on overlapping loops — the perceived loudness dips in the
/// middle of a crossfade, because power goes as the square of amplitude. `sin`/`cos` quarter
/// curves keep summed power constant when a rising and a falling ramp overlap. Writing
/// `volume` in one jump also clicks, hence stepping at ~60 Hz.
enum FadeRamp {
    enum Curve { case rising, falling }

    static func run(node: AVAudioPlayerNode,
                    from: Float,
                    to: Float,
                    curve: Curve,
                    duration: TimeInterval) async {
        guard duration > 0.01 else {
            node.volume = to
            return
        }

        await glide(duration: duration) { t in
            switch curve {
            case .rising:  node.volume = to * sin(t * .pi / 2)
            case .falling: node.volume = from * cos(t * .pi / 2)
            }
        }
        if !Task.isCancelled { node.volume = to }
    }

    /// Calls `apply` with progress 0…1 until `duration` has elapsed on the clock.
    ///
    /// Progress comes from elapsed time rather than from counting steps. Each `Task.sleep`
    /// overshoots a little, and counting steps added those overshoots up, so a 1.5 s fade
    /// really took noticeably longer — and a fade that is meant to overlap another no longer
    /// lines up with it. A late tick now just takes a bigger step.
    static func glide(duration: TimeInterval, _ apply: (Float) -> Void) async {
        let clock = ContinuousClock()
        let start = clock.now
        let total = Duration.seconds(duration)

        while !Task.isCancelled {
            let elapsed = clock.now - start
            if elapsed >= total { return }
            apply(Float(elapsed / total))
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}
