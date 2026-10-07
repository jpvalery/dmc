import Foundation
import Observation
import os

/// Where things that went wrong end up: in the unified log for a post-mortem, and in `issues`
/// for the rail, so a failed save is something the DM can see rather than something that quietly
/// did not happen.
enum Log {
    static let persistence = Logger(subsystem: "me.jpvalery.dmc", category: "persistence")
    static let audio = Logger(subsystem: "me.jpvalery.dmc", category: "audio")
    static let hotkeys = Logger(subsystem: "me.jpvalery.dmc", category: "hotkeys")
    static let network = Logger(subsystem: "me.jpvalery.dmc", category: "network")
}

@MainActor
@Observable
final class Diagnostics {
    static let shared = Diagnostics()

    /// Newest last. Capped so a failure that repeats on every keystroke cannot grow without bound.
    private(set) var issues: [String] = []

    private static let limit = 12

    func report(_ message: String) {
        guard !issues.contains(message) else { return }
        issues.append(message)
        if issues.count > Self.limit { issues.removeFirst(issues.count - Self.limit) }
    }

    func clear(matching prefix: String) {
        issues.removeAll { $0.hasPrefix(prefix) }
    }

    func dismiss(_ message: String) {
        issues.removeAll { $0 == message }
    }
}

/// Persistence code is not main-actor, but the UI that shows its failures is. This is the one
/// place that hops across.
func reportIssue(_ message: String) {
    Task { @MainActor in Diagnostics.shared.report(message) }
}
