import AppKit
import CoachCore

/// A click-through, always-on-top panel that never takes focus.
class ClickThroughPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Moves to a global top-left rect.
    func place(_ rect: CGRect) { setFrame(ScreenSpace.toAppKit(rect), display: true) }
}

/// The circle around a teaching target: solid green when the app reported the place, dashed amber when approximate.
final class GuideOverlayWindow: ClickThroughPanel {
    private final class Frame: NSView {
        var verified = false { didSet { needsDisplay = true } }
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 4 + 1.25, dy: 4 + 1.25))
            path.lineWidth = 2.5
            if !verified { path.setLineDash([7.5, 7.5], count: 2, phase: 0) } // WPF dashes are in stroke widths (3,3)
            (verified ? Palette.verified : Palette.approximate).setStroke()
            path.stroke()
        }
    }
    private let frameView = Frame()

    override init() {
        super.init()
        contentView = frameView
    }

    /// `target` is global top-left; the circle passes just outside its corners, as on Windows.
    func show(_ target: CGRect, verified: Bool) {
        guard CompanionPlacement.isUsable(target) else { return }
        frameView.verified = verified
        place(TargetSnap.circle(around: target).insetBy(dx: -4, dy: -4))
        orderFrontRegardless()
    }
}

/// Pip standing beside the target while teaching: moves there, points at it, passes clicks through,
/// and fades away when the pointer or a text caret comes close. Mirrors TeachingCompanionWindow.cs.
final class TeachingCompanionWindow: ClickThroughPanel {
    let pip = PipView(frame: .zero)
    var onMove: (() -> Void)?
    var reducedMotion = false
    private let caret = CaretTracker()
    private(set) var screenBounds = CGRect.zero
    private var from = CGRect.zero, destination = CGRect.zero, protected = CGRect.zero, panel: CGRect?
    private var started = Date()
    private var timer: Timer?

    override init() {
        super.init()
        contentView = pip
    }

    func follow(_ spot: CompanionSpot, target: CGRect, origin: CGRect?, panel: CGRect?) {
        self.panel = panel
        protected = CompanionPlacement.protectedArea(target, scale: 1)
        pip.setPointing(spot.direction)
        pip.setReducedMotion(reducedMotion)
        if isVisible, hypot(destination.minX - spot.bounds.minX, destination.minY - spot.bounds.minY) < 2, destination.size == spot.bounds.size { return }
        from = isVisible ? screenBounds : origin.map { CGRect(origin: $0.origin, size: spot.bounds.size) } ?? spot.bounds
        destination = spot.bounds
        if reducedMotion { from = destination }
        move(to: from)
        if !isVisible { orderFrontRegardless(); pip.windowDidShow(); caret.start() }
        started = Date()
        schedule(interval: 1.0 / 60)
        tick()
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let t = min(max(Date().timeIntervalSince(started) / 0.3, 0), 1)
        let eased = 1 - pow(1 - t, 3)
        pip.setTravelling(t < 1 && !reducedMotion ? travelDirection() : .none)
        let bounds = CGRect(x: from.minX + (destination.minX - from.minX) * eased, y: from.minY + (destination.minY - from.minY) * eased,
                            width: destination.width, height: destination.height)
        if bounds != screenBounds { move(to: bounds) }
        // Disappear before the pointer or a text caret reaches the artwork, and never cover the conversation panel.
        let yield = CompanionPlacement.shouldYield(sprite: screenBounds, protectedTarget: protected, cursor: ScreenSpace.cursor,
                                                   caret: caret.caret, scale: 1)
            || (panel.map { screenBounds.touches($0) } ?? false)
        alphaValue = yield ? 0 : 1
        if t >= 1, (timer?.timeInterval ?? 0) < 0.05 { schedule(interval: 0.08) }
    }

    private func travelDirection() -> PointingDirection {
        let dx = destination.minX - from.minX, dy = destination.minY - from.minY
        return abs(dx) > abs(dy) ? (dx < 0 ? .left : .right) : (dy < 0 ? .up : .down)
    }

    private func move(to rect: CGRect) {
        place(rect)
        screenBounds = rect
        onMove?()
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        caret.stop()
        super.close()
    }
}
