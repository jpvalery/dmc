import AppKit
import SwiftUI

/// The notepad's text view, driven for real: styling is laid over the text, cues resolve against
/// what exists, and a click lands on a cue only when it is actually on the cue.
@main
struct Probe {
    @MainActor
    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        UserDefaults.standard.set(CommandLine.arguments[1], forKey: "vault.path")
        Vault.bootstrap()
        _ = NSApplication.shared

        var fails = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("  \(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            if !ok { fails += 1 }
        }

        let page = """
        # Chapter 3

        Open on [[scene:Tavern]] and then a **loud** knock: [[effect:Door slam]].
        Say `hello` first. Unknown: [[scene:Nowhere]]. Quiet: [[stop]]
        - [ ] hand out the map
        - [x] roll for weather
        """

        var fired: [NoteTrigger] = []
        let notes = NotesStore()
        let editor = MarkdownEditor(notes: notes, readOnly: false,
                                    sceneNames: ["Tavern", "Crypt"], effectNames: ["Door slam"],
                                    onTrigger: { fired.append($0) })
        let coordinator = MarkdownEditor.Coordinator(editor)

        // The same stack `makeNSView` builds, in a real window so layout is real.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let textView = TriggerTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), textContainer: container)
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = MarkdownEditor.Style.body
        textView.onTrigger = { fired.append($0) }
        coordinator.textView = textView

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = textView
        textView.string = page
        coordinator.restyle()
        layout.ensureLayout(for: container)

        func range(of needle: String) -> NSRange { (page as NSString).range(of: needle) }
        func attr(_ key: NSAttributedString.Key, at needle: String) -> Any? {
            storage.attribute(key, at: range(of: needle).location + 1, effectiveRange: nil)
        }
        func font(at needle: String) -> NSFont? { attr(.font, at: needle) as? NSFont }
        func isBold(_ f: NSFont?) -> Bool { f.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false }

        // MARK: Styling
        check("a heading is bold and larger than body",
              isBold(font(at: "# Chapter 3")) && (font(at: "# Chapter 3")?.pointSize ?? 0) > MarkdownEditor.Style.size)
        check("body text is left plain", !isBold(font(at: "Open on")))
        check("**bold** is bold", isBold(font(at: "**loud**")))
        check("`code` gets a background", attr(.backgroundColor, at: "`hello`") != nil)
        check("a finished task is struck through",
              attr(.strikethroughStyle, at: "roll for weather") != nil && attr(.strikethroughStyle, at: "hand out the map") == nil)

        check("a cue that resolves is marked as a trigger",
              (attr(.dmcTrigger, at: "[[scene:Tavern]]") as? String) == "[[scene:Tavern]]")
        check("an effect cue resolves too", attr(.dmcTrigger, at: "[[effect:Door slam]]") != nil)
        check("stop always resolves", attr(.dmcTrigger, at: "[[stop]]") != nil)
        check("a cue naming nothing is not a trigger", attr(.dmcTrigger, at: "[[scene:Nowhere]]") == nil)
        check("…and is drawn differently from one that works",
              (attr(.foregroundColor, at: "[[scene:Nowhere]]") as? NSColor) != (attr(.foregroundColor, at: "[[scene:Tavern]]") as? NSColor))
        check("text outside a cue is not a trigger", attr(.dmcTrigger, at: "Open on") == nil)
        check("the file's text is untouched by styling", storage.string == page)

        // MARK: Clicking
        /// `NSTextView.mouseDown` runs a tracking loop until the button comes up, so the matching
        /// mouse-up is queued first or a click that is not a cue would wait forever.
        func send(_ down: NSEvent) {
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: down.locationInWindow,
                                        modifierFlags: down.modifierFlags, timestamp: 0,
                                        windowNumber: down.windowNumber, context: nil,
                                        eventNumber: 0, clickCount: 1, pressure: 0)!
            NSApp.postEvent(up, atStart: false)
            textView.mouseDown(with: down)
        }
        /// A mouse-down at the middle of `needle`, in window coordinates.
        func click(on needle: String, modifiers: NSEvent.ModifierFlags = [], offsetX: CGFloat = 0) {
            let glyphs = layout.glyphRange(forCharacterRange: range(of: needle), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            let origin = textView.textContainerOrigin
            let point = NSPoint(x: rect.midX + origin.x + offsetX, y: rect.midY + origin.y)
            let inWindow = textView.convert(point, to: nil as NSView?)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: inWindow, modifierFlags: modifiers,
                                           timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 0, clickCount: 1, pressure: 1)!
            send(event)
        }

        /// Where `needle` sits, in the text view's own coordinates.
        func point(of needle: String, offsetX: CGFloat = 0) -> NSPoint {
            let glyphs = layout.glyphRange(forCharacterRange: range(of: needle), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            let origin = textView.textContainerOrigin
            return NSPoint(x: rect.midX + origin.x + offsetX, y: rect.midY + origin.y)
        }

        // Through the real mouse-down, for the cases that return before AppKit's own tracking.
        textView.readsTriggersOnClick = false
        click(on: "[[scene:Tavern]]", modifiers: .command)
        check("⌘-click on a cue fires it while editing", fired == [.scene("Tavern")], "\(fired)")

        click(on: "[[effect:Door slam]]", modifiers: .command)
        click(on: "[[stop]]", modifiers: .command)
        check("effects and stop fire", fired == [.scene("Tavern"), .effect("Door slam"), .stopAll], "\(fired)")

        fired = []
        textView.readsTriggersOnClick = true
        click(on: "[[scene:Tavern]]")
        check("in reading mode a plain click fires the cue", fired == [.scene("Tavern")], "\(fired)")

        // Everything that must *not* fire, by asking the hit test directly: past a non-cue the
        // text view would hand the click to AppKit, whose tracking loop waits for a real mouse-up.
        check("hit test: a cue is found", textView.trigger(at: point(of: "[[scene:Tavern]]")) == .scene("Tavern"))
        check("hit test: ordinary text is not a cue", textView.trigger(at: point(of: "Open on")) == nil)
        check("hit test: a broken cue is not a cue", textView.trigger(at: point(of: "[[scene:Nowhere]]")) == nil)
        check("hit test: the blank space past the end of the line is not a cue",
              textView.trigger(at: point(of: "[[stop]]", offsetX: 160)) == nil)
        check("hit test: the margin is not a cue", textView.trigger(at: NSPoint(x: 2, y: 2)) == nil)

        // MARK: Restyling after an edit
        textView.string = page.replacingOccurrences(of: "[[scene:Nowhere]]", with: "[[scene:Crypt]]")
        coordinator.restyle()
        let edited = textView.string as NSString
        let at = edited.range(of: "[[scene:Crypt]]").location + 1
        check("a cue fixed by editing becomes live", storage.attribute(.dmcTrigger, at: at, effectiveRange: nil) != nil)

        // MARK: The cursor stays with its words when text is inserted elsewhere
        func mapped(_ at: Int, _ old: String, _ new: String) -> Int {
            MarkdownEditor.mapped(at, from: old as NSString, to: new as NSString)
        }
        let before = "# Day\n\n## Log\n- 20:14 a\n\n## Loot\n- sword"
        let after = "# Day\n\n## Log\n- 20:14 a\n- 20:15 b\n\n## Loot\n- sword"
        let swordAt = (before as NSString).range(of: "sword").location
        let movedTo = mapped(swordAt + 3, before, after)
        check("a cursor below an insertion moves down with its text",
              (after as NSString).substring(from: movedTo).hasPrefix("rd"), "\((after as NSString).substring(from: movedTo))")
        check("a cursor above an insertion stays put", mapped(3, before, after) == 3)
        check("a cursor at the very end stays at the end", mapped(before.count, before, after) == after.count)
        check("replacing everything lands in range", (0...3).contains(mapped(40, before, "abc")))

        print(fails == 0 ? "\n  all editor checks pass" : "\n  \(fails) FAILED")
    }
}
