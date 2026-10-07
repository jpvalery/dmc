import AppKit
import SwiftUI

/// A draggable 1pt divider with a grabbable hit area.
struct PaneDivider: View {
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                // A 1pt line is impossible to grab; widen the hit area, not the visible line.
                Rectangle()
                    .fill(.clear)
                    .frame(width: 11)
                    .contentShape(Rectangle())
                    // .set() rather than push/pop — push/pop unbalances when the pointer leaves
                    // during a drag and leaves a stuck resize cursor.
                    .onHover { $0 ? NSCursor.resizeLeftRight.set() : NSCursor.arrow.set() }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { onDrag($0.translation.width) }
                            .onEnded { _ in
                                onEnd()
                                NSCursor.arrow.set()
                            }
                    )
            }
    }
}
