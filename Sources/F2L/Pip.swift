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
