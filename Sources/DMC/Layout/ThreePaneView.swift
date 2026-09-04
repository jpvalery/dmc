import AppKit
import SwiftUI

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

/// Three panes at roughly 1:4:3 with draggable dividers whose positions persist.
///
/// Fractions rather than absolute widths, so the split survives a window resize or a move to an
/// external display. Either side pane can collapse: the rail shrinks to an icon-only strip, the
/// notes pane disappears entirely.
struct ThreePaneView<Rail: View, Web: View, Notes: View>: View {
    @AppStorage("pane.railFraction") private var railFraction: Double = 0.125
    @AppStorage("pane.notesFraction") private var notesFraction: Double = 0.375

    @State private var baseRail: Double?
    @State private var baseNotes: Double?

    private let collapsedRail: CGFloat = 56
    private let minRail: CGFloat = 132, maxRail: CGFloat = 320
    private let minNotes: CGFloat = 240
    private let minWeb: CGFloat = 380

    let railCollapsed: Bool
    let notesHidden: Bool
    let rail: Rail
    let web: Web
    let notes: Notes

    init(railCollapsed: Bool,
         notesHidden: Bool,
         @ViewBuilder rail: () -> Rail,
         @ViewBuilder web: () -> Web,
         @ViewBuilder notes: () -> Notes) {
        self.railCollapsed = railCollapsed
        self.notesHidden = notesHidden
        self.rail = rail()
        self.web = web()
        self.notes = notes()
    }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let w = widths(total: total)

            HStack(spacing: 0) {
                rail.frame(width: w.rail)

                // A collapsed rail has a fixed width, so its divider is decorative only.
                if railCollapsed {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                } else {
                    PaneDivider(
                        onDrag: { dx in
                            let base = baseRail ?? railFraction
                            if baseRail == nil { baseRail = base }
                            railFraction = (base * total + dx).clamped(minRail, maxRail) / total
                        },
                        onEnd: { baseRail = nil }
                    )
                }

                web.frame(width: w.web)

                if !notesHidden {
                    PaneDivider(
                        onDrag: { dx in
                            let base = baseNotes ?? notesFraction
                            if baseNotes == nil { baseNotes = base }
                            // Dragging right shrinks the notes pane.
                            notesFraction = max(base * total - dx, minNotes) / total
                        },
                        onEnd: { baseNotes = nil }
                    )
                    notes.frame(width: w.notes)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: railCollapsed)
            .animation(.easeInOut(duration: 0.18), value: notesHidden)
        }
    }

    /// Resolve fractions into widths, honouring per-pane minimums. When the window is too narrow
    /// to satisfy everything, space is taken from notes first and the rail second, because a
    /// squeezed VTT is the worst outcome.
    private func widths(total: CGFloat) -> (rail: CGFloat, web: CGFloat, notes: CGFloat) {
        var r = railCollapsed ? collapsedRail : (total * railFraction).clamped(minRail, maxRail)
        var n = notesHidden ? 0 : max(total * notesFraction, minNotes)
        let dividers: CGFloat = notesHidden ? 1 : 2
        var wb = total - r - n - dividers

        if wb < minWeb {
            let deficit = minWeb - wb
            let fromNotes = notesHidden ? 0 : min(deficit, n - minNotes)
            n -= fromNotes
            if !railCollapsed {
                r = max(minRail, r - (deficit - fromNotes))
            }
            wb = max(0, total - r - n - dividers)
        }
        return (r, wb, n)
    }
}
