import AppKit

/// A flat button matching the Windows style: rounded 10, no border, dims on hover and press.
final class FlatButton: NSButton {
    var fill: NSColor? { didSet { needsDisplay = true } }
    var ink: NSColor = Palette.ink { didSet { updateTitle() } }
    var textSize: CGFloat = 12 { didSet { updateTitle() } }
    var weight: NSFont.Weight = .regular { didSet { updateTitle() } }
    var padding = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    var cornerRadius: CGFloat = 10
    var onClick: (() -> Void)?
    private var hovering = false { didSet { refreshAlpha() } }
    private var pressed = false { didSet { refreshAlpha() } }

    init(_ title: String, size: CGFloat = 12, ink: NSColor = Palette.ink, fill: NSColor? = Palette.button) {
        super.init(frame: .zero)
        self.title = title
        self.textSize = size
        self.ink = ink
        self.fill = fill
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        focusRingType = .none
        target = self
        action = #selector(clicked)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var title: String { didSet { updateTitle() } }
    override var isEnabled: Bool { didSet { refreshAlpha() } }

    private func updateTitle() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Fonts.inter(textSize, weight), .foregroundColor: ink, .paragraphStyle: paragraph,
        ])
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let text = attributedTitle.size()
        return NSSize(width: ceil(text.width) + padding.left + padding.right, height: max(ceil(text.height) + padding.top + padding.bottom, 24))
    }

    override func draw(_ dirtyRect: NSRect) {
        if let fill {
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
        let text = attributedTitle.size()
        let alignment = (attributedTitle.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment ?? .center
        let x: CGFloat = alignment == .left ? padding.left : (bounds.width - text.width) / 2
        attributedTitle.draw(in: NSRect(x: x, y: (bounds.height - text.height) / 2, width: min(text.width, bounds.width - x), height: text.height))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {
        pressed = true
        super.mouseDown(with: event) // runs the tracking loop until mouse up
        pressed = false
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func refreshAlpha() { alphaValue = !isEnabled ? 0.4 : pressed ? 0.5 : hovering ? 0.72 : 1 }

    @objc private func clicked() { onClick?() }
}

/// A non-interactive text label in Inter.
func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, wraps: Bool = false) -> NSTextField {
    let label = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
    label.font = Fonts.inter(size, weight)
    label.textColor = color
    label.isSelectable = false
    label.drawsBackground = false
    label.isBordered = false
    if !wraps { label.lineBreakMode = .byTruncatingTail }
    return label
}

/// A plain rounded box drawn with a layer.
final class RoundedBox: NSView {
    init(fill: NSColor, radius: CGFloat, border: NSColor? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = radius
        if let border {
            layer?.borderColor = border.cgColor
            layer?.borderWidth = 1
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
}

/// A view whose subviews use top-left coordinates, so layout code reads like the XAML it mirrors.
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Closure-backed menu item target. The item keeps its action alive, so a menu rebuilt each time it opens frees the
/// old ones.
final class MenuAction: NSObject {
    private let handler: (NSMenuItem) -> Void
    private init(_ handler: @escaping (NSMenuItem) -> Void) { self.handler = handler }

    static func item(_ title: String, checked: Bool? = nil, handler: @escaping (NSMenuItem) -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        if let checked { item.state = checked ? .on : .off }
        return item
    }

    @objc private func run(_ sender: NSMenuItem) { handler(sender) }
}
