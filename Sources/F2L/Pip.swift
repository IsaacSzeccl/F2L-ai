import AppKit
import CoachCore
import QuartzCore

struct PipSprite {
    let image: CGImage
    let width: CGFloat
    let height: CGFloat
}

/// The 32 painted poses, cut from the two shared atlases using the precomputed frames.json.
enum PipSprites {
    static let expressions = load("expressions")
    static let directions = load("directions")

    private static func load(_ name: String) -> [PipSprite] {
        guard let pip = Assets.url("Pip"),
              let manifestData = try? Data(contentsOf: pip.appendingPathComponent("frames.json")),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let sheet = manifest[name] as? [String: Any], let frames = sheet["frames"] as? [[Int]],
              let source = CGImageSourceCreateWithURL(pip.appendingPathComponent("\(name).png") as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        else {
            Log.app.fault("Pip artwork \(name, privacy: .public) is missing")
            return []
        }
        let displayWidth = CGFloat(manifest["displayWidth"] as? Int ?? 288)
        let scale = displayWidth / (CGFloat(atlas.width) / 4)
        return frames.compactMap { f in
            guard f.count == 4, let image = atlas.cropping(to: CGRect(x: f[0], y: f[1], width: f[2], height: f[3])) else { return nil }
            return PipSprite(image: image, width: CGFloat(f[2]) * scale, height: CGFloat(f[3]) * scale)
        }
    }
}

/// Pip drawn from the painted sprites on a 320×340 canvas, scaled to fit. Same timings as Windows PipView.
final class PipView: NSView {
    private let sprite = CALayer()
    private var timer: Timer?
    private var started = Date()
    private var state = PipPose.State()
    private(set) var currentPose: PipPose?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(sprite)
        sprite.contentsGravity = .resize
        sprite.minificationFilter = .trilinear
        sprite.magnificationFilter = .linear
        draw(force: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Not flipped: layer contents draw upright in AppKit's bottom-left space.
    override func hitTest(_ point: NSPoint) -> NSView? { nil } // the host handles clicks and drags

    func setIntent(_ intent: QuestionIntent) { state.intent = intent; draw() }
    func setSpeaking(_ on: Bool) { guard state.speaking != on else { return }; state.speaking = on; restart() }
    func setListening(_ on: Bool) { guard state.listening != on else { return }; state.listening = on; restart() }
    func setThinking(_ on: Bool) { guard state.thinking != on else { return }; state.thinking = on; restart() }
    func setWaving(_ on: Bool) { guard state.waving != on else { return }; state.waving = on; restart() }
    func setPointing(_ direction: PointingDirection) { state.pointing = direction; draw() }
    func setTravelling(_ direction: PointingDirection) { state.travelling = direction; draw() }
    func setReducedMotion(_ on: Bool) { state.reducedMotion = on; draw() }

    private func restart() { started = Date(); draw() }

    override func layout() {
        super.layout()
        draw(force: true)
    }

    // Animate only while Pip is actually on screen; hidden or covered Pip costs nothing.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        visibilityChanged()
    }
    override func viewDidHide() { visibilityChanged() }
    override func viewDidUnhide() { visibilityChanged() }

    @objc private func visibilityChanged() {
        let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } == true && !isHiddenOrHasHiddenAncestor
        if visible, timer == nil {
            draw()
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.draw() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !visible {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Call after showing the window: occlusion updates arrive asynchronously.
    func windowDidShow() { visibilityChanged() }

    private func draw(force: Bool = false) {
        let pose = PipPose.at(milliseconds: Int(Date().timeIntervalSince(started) * 1000), state)
        guard force || pose != currentPose else { return }
        let frames = pose.directions ? PipSprites.directions : PipSprites.expressions
        guard frames.indices.contains(pose.frame) else { return }
        let image = frames[pose.frame]
        currentPose = pose
        // Uniform fit of the 320×340 canvas into our bounds, centred (WPF Viewbox Stretch=Uniform).
        let fit = min(bounds.width / 320, bounds.height / 340)
        let origin = CGPoint(x: (bounds.width - 320 * fit) / 2, y: (bounds.height - 340 * fit) / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = image.image
        sprite.contentsScale = window?.backingScaleFactor ?? 2
        // Canvas placement as on Windows: centred horizontally, feet on a baseline 325 units down (15 up).
        sprite.frame = CGRect(x: origin.x + (320 - image.width) / 2 * fit, y: origin.y + (340 - 325) * fit,
                              width: image.width * fit, height: image.height * fit)
        sprite.setAffineTransform(pose.mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        CATransaction.commit()
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

/// Pip's own emotes, used where an app would otherwise show a system emoji: a painted Pip pose with a small drawn
/// accent in Pip's colours. `F2L --export-emotes <dir>` writes them as PNGs for the Windows app
/// (Windows/F2L.Windows/Assets/Pip/Emotes), so both apps show the same pictures.
enum PipEmote: String, CaseIterable {
    case hello, happy, cheer, thinking, curious, focused

    /// Pose in expressions.png (see ARTWORK.md for the 16 poses).
    var frame: Int {
        switch self {
        case .hello: 14
        case .happy: 3
        case .cheer: 15
        case .thinking: 4
        case .curious: 8
        case .focused: 12
        }
    }

    static let amber = Palette.hex(0xF2A33A), teal = Palette.hex(0x2F8F86), ink = Palette.hex(0x5B4636)

    /// The emote at `side` points, transparent background, Pip's feet on the bottom edge.
    func image(side: CGFloat = 48) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: true) { bounds in
            let s = bounds.width
            if PipSprites.expressions.indices.contains(frame), let context = NSGraphicsContext.current?.cgContext {
                let sprite = PipSprites.expressions[frame]
                let scale = min(s * 0.84 / sprite.height, s * 0.84 / sprite.width)
                let rect = CGRect(x: (s - sprite.width * scale) / 2 - s * 0.04, y: s - sprite.height * scale - s * 0.02,
                                  width: sprite.width * scale, height: sprite.height * scale)
                context.saveGState()
                // CGImage draws bottom-up; flip just for the sprite.
                context.translateBy(x: 0, y: rect.maxY + rect.minY)
                context.scaleBy(x: 1, y: -1)
                context.draw(sprite.image, in: rect)
                context.restoreGState()
            }
            drawAccent(in: s)
            return true
        }
    }

    private func drawAccent(in s: CGFloat) {
        let line = max(1.5, s * 0.045)
        func sparkle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: NSColor) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: cx, y: cy - r)); path.curve(to: NSPoint(x: cx + r, y: cy), controlPoint1: NSPoint(x: cx + r * 0.18, y: cy - r * 0.18), controlPoint2: NSPoint(x: cx + r * 0.18, y: cy - r * 0.18))
            path.curve(to: NSPoint(x: cx, y: cy + r), controlPoint1: NSPoint(x: cx + r * 0.18, y: cy + r * 0.18), controlPoint2: NSPoint(x: cx + r * 0.18, y: cy + r * 0.18))
            path.curve(to: NSPoint(x: cx - r, y: cy), controlPoint1: NSPoint(x: cx - r * 0.18, y: cy + r * 0.18), controlPoint2: NSPoint(x: cx - r * 0.18, y: cy + r * 0.18))
            path.curve(to: NSPoint(x: cx, y: cy - r), controlPoint1: NSPoint(x: cx - r * 0.18, y: cy - r * 0.18), controlPoint2: NSPoint(x: cx - r * 0.18, y: cy - r * 0.18))
            color.setFill(); path.fill()
        }
        switch self {
        case .hello:
            // Little motion lines beside the waving hand, and a small sparkle.
            for (from, to) in [((0.84, 0.30), (0.93, 0.22)), ((0.87, 0.42), (0.98, 0.40))] {
                let dash = NSBezierPath()
                dash.move(to: NSPoint(x: s * from.0, y: s * from.1)); dash.line(to: NSPoint(x: s * to.0, y: s * to.1))
                dash.lineWidth = line * 1.2; dash.lineCapStyle = .round
                Self.amber.setStroke(); dash.stroke()
            }
            sparkle(s * 0.14, s * 0.18, s * 0.08, Self.teal)
        case .happy:
            let heart = NSBezierPath()
            let cx = s * 0.84, cy = s * 0.20, r = s * 0.09
            heart.move(to: NSPoint(x: cx, y: cy + r * 1.1))
            heart.curve(to: NSPoint(x: cx - r * 1.1, y: cy - r * 0.2), controlPoint1: NSPoint(x: cx - r * 0.6, y: cy + r * 0.6), controlPoint2: NSPoint(x: cx - r * 1.2, y: cy + r * 0.3))
            heart.curve(to: NSPoint(x: cx, y: cy - r * 0.4), controlPoint1: NSPoint(x: cx - r * 1.0, y: cy - r * 1.0), controlPoint2: NSPoint(x: cx - r * 0.2, y: cy - r * 0.9))
            heart.curve(to: NSPoint(x: cx + r * 1.1, y: cy - r * 0.2), controlPoint1: NSPoint(x: cx + r * 0.2, y: cy - r * 0.9), controlPoint2: NSPoint(x: cx + r * 1.0, y: cy - r * 1.0))
            heart.curve(to: NSPoint(x: cx, y: cy + r * 1.1), controlPoint1: NSPoint(x: cx + r * 1.2, y: cy + r * 0.3), controlPoint2: NSPoint(x: cx + r * 0.6, y: cy + r * 0.6))
            Palette.hex(0xE07A5F).setFill(); heart.fill()
        case .cheer:
            sparkle(s * 0.84, s * 0.16, s * 0.12, Self.amber)
            sparkle(s * 0.12, s * 0.22, s * 0.08, Self.teal)
            sparkle(s * 0.92, s * 0.42, s * 0.06, Self.teal)
        case .thinking:
            for (i, r) in [0.035, 0.05, 0.065].enumerated() {
                let dot = NSBezierPath(ovalIn: NSRect(x: s * (0.70 + Double(i) * 0.09) - s * r, y: s * (0.30 - Double(i) * 0.09) - s * r, width: s * r * 2, height: s * r * 2))
                Self.teal.setFill(); dot.fill()
            }
        case .curious:
            let mark = NSAttributedString(string: "?", attributes: [.font: NSFont.systemFont(ofSize: s * 0.36, weight: .heavy), .foregroundColor: Self.teal])
            mark.draw(at: NSPoint(x: s * 0.74, y: s * -0.02))
        case .focused:
            let ring = NSBezierPath(ovalIn: NSRect(x: s * 0.72, y: s * 0.06, width: s * 0.22, height: s * 0.22))
            ring.lineWidth = line; Self.amber.setStroke(); ring.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: s * 0.80, y: s * 0.14, width: s * 0.06, height: s * 0.06))
            Self.amber.setFill(); dot.fill()
        }
    }

    /// Writes every emote as `<name>.png` (256 px, transparent).
    static func export(to directory: URL) -> [String] {
        // Without the painted poses the PNGs would be accents only; never overwrite good emotes with those.
        guard PipSprites.expressions.count == 16 else { return ["Pip's artwork (expressions.png) didn't load; nothing exported"] }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var failures: [String] = []
        for emote in allCases {
            let image = emote.image(side: 256)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
                failures.append("could not draw \(emote.rawValue)"); continue
            }
            rep.size = NSSize(width: 256, height: 256)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = rep.representation(using: .png, properties: [:]),
                  (try? png.write(to: directory.appendingPathComponent("\(emote.rawValue).png"))) != nil else {
                failures.append("could not save \(emote.rawValue)"); continue
            }
        }
        return failures
    }
}
