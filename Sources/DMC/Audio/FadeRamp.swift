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

        let steps = max(2, Int(duration * 60))
        let tick = Duration.milliseconds(1000 / 60)

        for i in 1...steps {
            if Task.isCancelled { return }
            let t = Float(i) / Float(steps)
            switch curve {
            case .rising:  node.volume = to * sin(t * .pi / 2)
            case .falling: node.volume = from * cos(t * .pi / 2)
            }
            try? await Task.sleep(for: tick)
        }
        if !Task.isCancelled { node.volume = to }
    }
}
