import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// Marks a `[[scene:…]]` span with the trigger it stands for.
    static let dmcTrigger = NSAttributedString.Key("dmc.trigger")
}

/// The notepad's text view: plain markdown on disk, lightly styled on screen, with `[[scene:…]]`
/// cues that play things when clicked.
///
/// A plain `TextEditor` can neither style the text nor react to a click on part of it, hence
/// AppKit. The file is still just the characters typed — styling is attributes laid over them and
/// never written out.
///
/// While editing, ⌘-click fires a cue so a click can still put the cursor in it. In reading mode
/// the text is not editable and a plain click fires it.
struct MarkdownEditor: NSViewRepresentable {
    var notes: NotesStore
    var readOnly: Bool
    /// What the cues can resolve against, so one that names nothing is drawn as broken.
    var sceneNames: [String]
    var effectNames: [String]
    var onTrigger: (NoteTrigger) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1, built by hand: the click handling needs the layout manager.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = TriggerTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.font = Style.body
        textView.onTrigger = { context.coordinator.parent.onTrigger($0) }
        context.coordinator.textView = textView

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }

        textView.isEditable = !readOnly
        textView.readsTriggersOnClick = readOnly

        var needsStyle = false

        var switchedNote = false
        if notes.selected?.id != coordinator.shownNote {
            // A different note: forget the last one's undo history, or ⌘Z would paste it back.
            coordinator.shownNote = notes.selected?.id
            textView.undoManager?.removeAllActions()
            switchedNote = true
        }

        if textView.string != notes.text {
            let old = textView.string as NSString
            let new = notes.text as NSString
            let selection = textView.selectedRange()
            coordinator.programmatic = true
            textView.string = notes.text
            coordinator.programmatic = false

            if switchedNote {
                // Somewhere new: start at the top.
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollToBeginningOfDocument(nil)
            } else {
                // The text changed under the cursor (a log line appended, say): keep the cursor
                // with the words it was in, not at the same number of characters from the top.
                let location = Self.mapped(selection.location, from: old, to: new)
                textView.setSelectedRange(NSRange(location: location, length: 0))
            }
            needsStyle = true
        }

        let names = sceneNames + ["\u{1F}"] + effectNames
        if names != coordinator.lastNames {
            coordinator.lastNames = names
            needsStyle = true
        }

        if needsStyle { coordinator.restyle() }

        if let request = notes.insertRequest, request.id != coordinator.handledInsert {
            coordinator.handledInsert = request.id
            if !readOnly {
                textView.window?.makeFirstResponder(textView)
                textView.insertText(request.text, replacementRange: textView.selectedRange())
            }
        }
    }

    /// Where a cursor at `location` in `old` belongs in `new`, taking the change to be everything
    /// between the text the two share at the start and at the end.
    static func mapped(_ location: Int, from old: NSString, to new: NSString) -> Int {
        let oldLength = old.length, newLength = new.length
        var prefix = 0
        while prefix < min(oldLength, newLength), old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(oldLength, newLength) - prefix,
              old.character(at: oldLength - 1 - suffix) == new.character(at: newLength - 1 - suffix) {
            suffix += 1
        }
        if location <= prefix { return location }
        // Inside the changed span: the best guess is the end of what replaced it.
        if location >= oldLength - suffix { return min(max(location + newLength - oldLength, 0), newLength) }
        return min(prefix + (newLength - prefix - suffix), newLength)
    }

    // MARK: Styling

    enum Style {
        static let size: CGFloat = 13
        static let body = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        static func font(_ weight: NSFont.Weight, scale: CGFloat = 1, italic: Bool = false) -> NSFont {
            let base = NSFont.monospacedSystemFont(ofSize: size * scale, weight: weight)
            guard italic else { return base }
            let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: size * scale) ?? base
        }

        static let heading = try! NSRegularExpression(pattern: #"^(#{1,6})[ \t]+.*$"#, options: .anchorsMatchLines)
        static let bold = try! NSRegularExpression(pattern: #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)
        static let italic = try! NSRegularExpression(pattern: #"(?<![\*\w])[\*_](?=[^\s\*_])(.+?)(?<=[^\s\*_])[\*_](?![\*\w])"#)
        static let code = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
        static let task = try! NSRegularExpression(pattern: #"^([ \t]*[-*][ \t]+)\[( |x|X)\](.*)$"#, options: .anchorsMatchLines)
        static let quote = try! NSRegularExpression(pattern: #"^>.*$"#, options: .anchorsMatchLines)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: TriggerTextView?
        /// True while the view's text is being set from the store, so it is not echoed back.
        var programmatic = false
        var lastNames: [String] = []
        var handledInsert: UUID?
        var shownNote: String?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !programmatic, let textView else { return }
            parent.notes.text = textView.string
            restyle()
        }

        /// Lays styling over the whole text. Notes are small, so this is cheap enough to do on
        /// every change; very large pastes skip it rather than stall typing.
        func restyle() {
            guard let textView, let storage = textView.textStorage else { return }
            guard !textView.hasMarkedText(), storage.length < 200_000 else { return }

            let full = NSRange(location: 0, length: storage.length)
            let text = storage.string
            let sceneNames = parent.sceneNames
            let effectNames = parent.effectNames
            let dim = NSColor.tertiaryLabelColor

            storage.beginEditing()
            storage.setAttributes([.font: Style.body, .foregroundColor: NSColor.labelColor], range: full)

            Style.heading.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                let level = match.range(at: 1).length
                let scale: CGFloat = [1.45, 1.25, 1.1, 1.0, 1.0, 1.0][level - 1]
                storage.addAttribute(.font, value: Style.font(.bold, scale: scale), range: match.range)
                storage.addAttribute(.foregroundColor, value: dim, range: match.range(at: 1))
            }
            Style.quote.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
            }
            Style.task.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.foregroundColor, value: dim, range: match.range(at: 1))
                if text[Range(match.range(at: 2), in: text)!] != " " {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                         range: match.range(at: 3))
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                         range: match.range(at: 3))
                }
            }
            Style.bold.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.font, value: Style.font(.bold), range: match.range)
            }
            Style.italic.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.font, value: Style.font(.regular, italic: true), range: match.range)
            }
            Style.code.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: match.range)
            }

            NoteLinks.pattern.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                let kind = (text as NSString).substring(with: match.range(at: 1))
                let nameRange = match.range(at: 2)
                let name = nameRange.location == NSNotFound
                    ? nil : (text as NSString).substring(with: nameRange)
                guard let trigger = NoteLinks.trigger(kind: kind, name: name) else { return }

                let resolves: Bool
                switch trigger {
                case .scene(let n): resolves = NoteLinks.match(n, in: sceneNames) != nil
                case .effect(let n): resolves = NoteLinks.match(n, in: effectNames) != nil
                case .stopAll: resolves = true
                }

                let color: NSColor = resolves ? .controlAccentColor : .systemRed
                storage.addAttributes([
                    .foregroundColor: color,
                    .backgroundColor: color.withAlphaComponent(0.13),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: color.withAlphaComponent(0.5),
                    .toolTip: resolves
                        ? "Click to run (⌘-click while editing)"
                        : "Nothing in this campaign is called that",
                ], range: match.range)
                if resolves {
                    storage.addAttribute(.dmcTrigger, value: trigger.markup, range: match.range)
                }
            }
            storage.endEditing()

            // What is typed next should be plain, not inherit a cue's colour.
            textView.typingAttributes = [.font: Style.body, .foregroundColor: NSColor.labelColor]
        }
    }
}

/// An `NSTextView` that can tell when a click lands on a cue.
final class TriggerTextView: NSTextView {
    var onTrigger: ((NoteTrigger) -> Void)?
    /// In reading mode a plain click fires a cue; otherwise it takes ⌘.
    var readsTriggersOnClick = false

    override func mouseDown(with event: NSEvent) {
        if (readsTriggersOnClick || event.modifierFlags.contains(.command)),
           let trigger = trigger(at: convert(event.locationInWindow, from: nil)) {
            onTrigger?(trigger)
            return
        }
        super.mouseDown(with: event)
    }

    /// The cue under `point`, if there is one. Checks the glyph's own rectangle as well as the
    /// index, because clicking in the blank space after a line otherwise reports its last character.
    /// Internal so the verification harness can ask it directly.
    func trigger(at point: NSPoint) -> NoteTrigger? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)

        let glyph = layout.glyphIndex(for: local, in: container)
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard rect.contains(local) else { return nil }

        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length,
              let markup = storage.attribute(.dmcTrigger, at: index, effectiveRange: nil) as? String
        else { return nil }

        let range = NSRange(location: 0, length: (markup as NSString).length)
        guard let match = NoteLinks.pattern.firstMatch(in: markup, range: range) else { return nil }
        let kind = (markup as NSString).substring(with: match.range(at: 1))
        let nameRange = match.range(at: 2)
        let name = nameRange.location == NSNotFound ? nil : (markup as NSString).substring(with: nameRange)
        return NoteLinks.trigger(kind: kind, name: name)
    }
}
