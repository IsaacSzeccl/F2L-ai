import AppKit

/// The question box: Enter sends, Shift+Enter adds a line, and Enter that confirms IME typing never sends.
final class ComposerTextView: NSTextView {
    var onSend: (() -> Void)?
    var onTextChange: (() -> Void)?
    var placeholder = "Ask anything about your screen…"

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !event.modifierFlags.contains(.shift), !hasMarkedText() {
            if !event.isARepeat { onSend?() }
            return
        }
        super.keyDown(with: event)
    }

    /// F2L runs without a visible menu bar, so handle the standard editing shortcuts here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: event) }
        switch key {
        case "x": cut(nil)
        case "c": copy(nil)
        case "v": pasteAsPlainText(nil)
        case "a": selectAll(nil)
        case "z": undoManager?.undo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        onTextChange?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        NSAttributedString(string: placeholder, attributes: [.font: Fonts.inter(13), .foregroundColor: Palette.hex(0x9497A0)])
            .draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height + 1))
    }

    /// Height of the typed text, for growing the box between its minimum and maximum.
    var contentHeight: CGFloat {
        guard let manager = layoutManager, let container = textContainer else { return 0 }
        manager.ensureLayout(for: container)
        return manager.usedRect(for: container).height + textContainerInset.height * 2
    }

    static func make() -> (NSScrollView, ComposerTextView) {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let text = ComposerTextView(frame: .zero)
        text.isRichText = false
        text.importsGraphics = false
        text.allowsUndo = true
        text.drawsBackground = false
        text.font = Fonts.inter(14)
        text.textColor = Palette.ink
        text.insertionPointColor = Palette.ink
        text.selectedTextAttributes = [.backgroundColor: Palette.selection]
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.setAccessibilityLabel("Ask Pip a follow-up")
        scroll.documentView = text
        return (scroll, text)
    }
}
