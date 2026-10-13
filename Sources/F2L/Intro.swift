import AppKit
import CoachCore

/// A native animated wordmark: Pip conducts the letters, then walks to the resting companion.
/// Native type stays sharp; original painted branding sits behind it. Previews use the real launch clock.
@MainActor
final class IntroWindow: NSPanel {
    static let title = "F2L AI"
    static let subtitle = "A teaching companion"
    private static let walkStart = 3.7
    private static let walkDuration = 2.35

    private final class Stage: FlippedView {
        var onClick: (() -> Void)?
        var paint: ((CGSize) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick?() }
        override func accessibilityPerformPress() -> Bool { onClick?(); return true }
        override func draw(_ dirtyRect: NSRect) { paint?(bounds.size) }
    }

    private let stage = Stage()
    /// Behind the painted letters: the dark wash with the dusk landscape, as layers, so the screen-sized picture is
    /// composited by the graphics card instead of being redrawn 60 times a second.
    private let backdrop = FlippedView()
    private let landscape = CALayer()
    /// Warm light from Pip, rather than a flat full-screen wash; also a layer, for the same reason.
    private let glow = CAGradientLayer()
    private let pip = PipView(frame: .zero)
    private let screenRect: CGRect
    private let home: CGRect
    private let reducedMotion: Bool
    private var timer: Timer?
    private var started = Date()
    private var seconds = 0.0
    private var completion: (() -> Void)?

    init(home: CGRect, reducedMotion: Bool) {
        let center = CGPoint(x: home.midX, y: home.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(NSPoint(x: center.x, y: ScreenSpace.primaryHeight - center.y), $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        screenRect = ScreenSpace.toTopLeft(screen.frame)
        self.home = home
        self.reducedMotion = reducedMotion
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        title = Self.title
        let container = NSView()
        container.wantsLayer = true
        contentView = container
        for view in [backdrop, stage] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = Palette.hex(0x191923, alpha: 0.94).cgColor
        backdrop.layer?.opacity = 0
        landscape.contents = BrandArtwork.cgImage(BrandArtwork.landscape)
        landscape.contentsGravity = .resizeAspectFill
        landscape.opacity = 0.7
        landscape.actions = ["bounds": NSNull(), "position": NSNull(), "opacity": NSNull()]
        backdrop.layer?.addSublayer(landscape)
        glow.type = .radial
        glow.colors = [Palette.hex(0x827088, alpha: 0.32).cgColor, Palette.hex(0x827088, alpha: 0.1).cgColor, Palette.hex(0x827088, alpha: 0).cgColor]
        glow.locations = [0, 0.5, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.actions = ["bounds": NSNull(), "position": NSNull()]
        backdrop.layer?.addSublayer(glow)
        stage.wantsLayer = true
        stage.addSubview(pip)
        stage.onClick = { [weak self] in self?.finish() }
        stage.paint = { [weak self] size in self?.paint(size) }
        stage.setAccessibilityRole(.button)
        stage.setAccessibilityLabel("\(Self.title). \(Self.subtitle). Skip intro.")
        pip.setReducedMotion(reducedMotion)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func play(_ completion: @escaping () -> Void) {
        self.completion = completion
        setFrame(ScreenSpace.toAppKit(screenRect), display: true)
        update(at: 0)
        orderFrontRegardless()
        pip.windowDidShow()
        started = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = Date().timeIntervalSince(self.started)
                if t >= (self.reducedMotion ? 1.8 : Self.walkStart + Self.walkDuration) { self.finish() }
                else { self.update(at: t) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func ease(_ x: Double) -> Double { let x = min(max(x, 0), 1); return x * x * (3 - 2 * x) }
    private func spring(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        return x == 1 ? 1 : 1 - exp(-6 * x) * cos(10 * x)
    }
    private var walkProgress: Double { reducedMotion ? 0 : ease((seconds - Self.walkStart) / Self.walkDuration) }
    private var backdropAlpha: Double {
        reducedMotion ? min(ease(seconds / 0.2), 1 - ease((seconds - 1.55) / 0.25))
            : ease(seconds / 0.3) * (1 - ease((seconds - Self.walkStart) / 0.85))
    }

    /// A shared group keeps the wordmark and Pip beside each other on smaller displays, too.
    private func layout(_ size: CGSize) -> (unit: CGFloat, origin: CGPoint, pip: CGRect) {
        let unit = min(1, size.width / 850, size.height / 560)
        let origin = CGPoint(x: (size.width - 610 * unit) / 2, y: size.height * 0.44 - 76 * unit)
        return (unit, origin, CGRect(x: origin.x + 396 * unit, y: origin.y - 32 * unit, width: 202 * unit, height: 215 * unit))
    }

    private func pipRect(_ size: CGSize, progress: Double) -> CGRect {
        let start = layout(size).pip
        let end = home.offsetBy(dx: -screenRect.minX, dy: -screenRect.minY)
        let p = CGFloat(progress)
        let arc = sin(p * .pi) * 48 * layout(size).unit
        let stride = sin(p * .pi * 14) * 4 * sin(p * .pi)
        return CGRect(x: start.minX + (end.minX - start.minX) * p,
                      y: start.minY + (end.minY - start.minY) * p - arc + stride,
                      width: start.width + (end.width - start.width) * p,
                      height: start.height + (end.height - start.height) * p)
    }

    private func update(at time: Double) {
        seconds = max(0, time)
        let size = stage.bounds.size
        let start = layout(size).pip
        if seconds < Self.walkStart || reducedMotion {
            let pop = reducedMotion ? 1 : spring((seconds - 0.08) / 0.7)
            let scale = 0.55 + 0.45 * pop
            let conducting = reducedMotion ? 0 : sin(max(0, seconds - 0.3) * 11) * 5 * ease((seconds - 0.3) / 0.2) * (1 - ease((seconds - 2.1) / 0.4))
            pip.frame = CGRect(x: start.midX - start.width * scale / 2,
                               y: start.maxY - start.height * scale + conducting,
                               width: start.width * scale, height: start.height * scale)
            pip.alphaValue = reducedMotion ? backdropAlpha : ease((seconds - 0.08) / 0.2)
            pip.setTravelling(.none)
            pip.setWaving(true)
        } else {
            pip.setWaving(false)
            let dx = home.midX - screenRect.minX - start.midX
            pip.setTravelling(walkProgress < 0.99 ? (abs(dx) > 80 ? (dx < 0 ? .left : .right) : .down) : .none)
            pip.frame = pipRect(size, progress: walkProgress)
            pip.alphaValue = 1
        }
        stage.needsDisplay = true
    }

    private func paint(_ size: CGSize) {
        let (unit, origin, start) = layout(size)
        let alpha = backdropAlpha
        // The wash and the landscape are layers behind this view (see `backdrop`); only their fade is set here.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.layer?.opacity = Float(alpha)
        landscape.frame = backdrop.bounds
        glow.frame = CGRect(x: origin.x + (300 - 440) * unit, y: origin.y + (80 - 300) * unit, width: 880 * unit, height: 600 * unit)
        CATransaction.commit()

        let exit = reducedMotion ? 0 : ease((seconds - 3.08) / 0.5)
        BrandArtwork.image("Brand/learning-doorway.png")?.draw(
            in: CGRect(x: origin.x + 126 * unit, y: origin.y - 100 * unit, width: 84 * unit, height: 84 * unit),
            from: .zero, operation: .sourceOver, fraction: alpha * (1 - exit), respectFlipped: true, hints: nil)
        let letters = ["F", "2", "L", "A", "I"]
        var x = origin.x
        for (i, letter) in letters.enumerated() {
            if i == 3 { x += 23 * unit }
            let font = Fonts.inter(88 * unit, .semibold)
            let width = (letter as NSString).size(withAttributes: [.font: font]).width
            let appear = reducedMotion ? 1 : spring((seconds - 0.32 - Double(i) * 0.15) / 0.65)
            let opacity = reducedMotion ? alpha : ease((seconds - 0.32 - Double(i) * 0.15) / 0.18) * (1 - ease((seconds - 3.05 - Double(i) * 0.065) / 0.4))
            let lift = reducedMotion ? 0 : 58 * (1 - appear) - 24 * ease((seconds - 3.05 - Double(i) * 0.065) / 0.4)
            drawText(letter, at: CGPoint(x: x + width / 2, y: origin.y + 54 * unit + lift * unit), font: font,
                     color: Palette.hex(i < 3 ? 0xFFFAF3 : 0xEDC98F, alpha: opacity),
                     scale: reducedMotion ? 1 : 0.72 + 0.28 * appear,
                     angle: reducedMotion ? 0 : (i.isMultiple(of: 2) ? -0.12 : 0.1) * (1 - appear))
            // A little burst at each letter's landing, tied to its own entrance.
            let burst = (seconds - 0.66 - Double(i) * 0.15) / 0.45
            if !reducedMotion, burst > 0, burst < 1 {
                spark(at: CGPoint(x: x + width * 0.7, y: origin.y - 8 * unit - 15 * burst * unit),
                      radius: (3 + 5 * burst) * unit, opacity: sin(burst * .pi) * 0.7)
            }
            x += width + 3 * unit
        }

        var wordX = origin.x + 3 * unit
        for (i, word) in Self.subtitle.split(separator: " ").enumerated() {
            let font = Fonts.inter(23 * unit, .medium)
            let text = String(word)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            let p = reducedMotion ? 1 : spring((seconds - 1.3 - Double(i) * 0.16) / 0.55)
            let opacity = reducedMotion ? alpha : ease((seconds - 1.3 - Double(i) * 0.16) / 0.18) * (1 - exit)
            drawText(text, at: CGPoint(x: wordX + width / 2, y: origin.y + 129 * unit + (reducedMotion ? 0 : 24 * (1 - p) * unit)),
                     font: font, color: Palette.hex(0xDED7E8, alpha: opacity), scale: 1, angle: 0)
            wordX += width + 7 * unit
        }

        // Pip's conducting stroke draws under the name, then disappears before the walk.
        let stroke = reducedMotion ? 1 : ease((seconds - 1.7) / 0.65)
        if stroke > 0 {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: origin.x + 4 * unit, y: origin.y + 163 * unit))
            path.curve(to: CGPoint(x: origin.x + (4 + 300 * stroke) * unit, y: origin.y + 161 * unit),
                       controlPoint1: CGPoint(x: origin.x + 80 * stroke * unit, y: origin.y + 169 * unit),
                       controlPoint2: CGPoint(x: origin.x + 210 * stroke * unit, y: origin.y + 153 * unit))
            path.lineWidth = 2.5 * unit; path.lineCapStyle = .round
            Palette.hex(0xEDC98F, alpha: 0.7 * (reducedMotion ? alpha : 1 - exit)).setStroke(); path.stroke()
            spark(at: CGPoint(x: origin.x + 324 * unit, y: origin.y + 160 * unit), radius: 6 * unit, opacity: stroke * (reducedMotion ? alpha : 1 - exit))
        }

        if !reducedMotion {
            for i in 0..<5 {
                let phase = seconds * 1.3 + Double(i) * 1.8
                let radius = (i.isMultiple(of: 2) ? 5.0 : 3.0) * unit
                spark(at: CGPoint(x: start.midX + cos(Double(i) * 2.1) * 135 * unit,
                                  y: start.midY + sin(Double(i) * 2.1) * 110 * unit + sin(phase) * 8 * unit),
                      radius: radius, opacity: ease((seconds - 0.6) / 0.5) * alpha * (0.35 + 0.2 * sin(phase)))
            }
            // Footstep lights linger briefly behind Pip; no overlay remains after handoff.
            for i in 0..<12 {
                let born = Self.walkStart + Double(i) * 0.17
                let age = seconds - born
                if age >= 0, age < 0.6 {
                    let rect = pipRect(size, progress: ease((born - Self.walkStart) / Self.walkDuration))
                    spark(at: CGPoint(x: rect.midX, y: rect.maxY - 9), radius: 4 * (1 - age / 0.6), opacity: (1 - age / 0.6) * 0.65)
                }
            }
        }
        drawText("Click anywhere to skip", at: CGPoint(x: size.width / 2, y: size.height - 42), font: Fonts.inter(12),
                 color: Palette.hex(0xDBD5E3, alpha: alpha * 0.6), scale: 1, angle: 0)
    }

    private func drawText(_ text: String, at center: CGPoint, font: NSFont, color: NSColor, scale: CGFloat, angle: CGFloat) {
        guard color.alphaComponent > 0 else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: angle)
        transform.scale(by: scale)
        transform.concat()
        (text as NSString).draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func spark(at center: CGPoint, radius: CGFloat, opacity: CGFloat) {
        let path = NSBezierPath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4
            let r = i.isMultiple(of: 2) ? radius : radius * 0.24
            let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        Palette.hex(0xF4D79D, alpha: opacity).setFill(); path.fill()
    }

    func finish() {
        timer?.invalidate(); timer = nil
        pip.setTravelling(.none); pip.setWaving(false)
        orderOut(nil)
        // The backdrop is shown once per launch: let its screen-sized picture go.
        landscape.contents = nil
        BrandArtwork.forget(BrandArtwork.landscape)
        let completion = self.completion
        self.completion = nil
        completion?()
    }

    /// Samples the actual animation without running the intro clock.
    func freeze(at seconds: Double) {
        timer?.invalidate(); timer = nil
        setFrame(ScreenSpace.toAppKit(screenRect), display: true)
        update(at: seconds)
        orderFrontRegardless()
        stage.displayIfNeeded()
    }
}
