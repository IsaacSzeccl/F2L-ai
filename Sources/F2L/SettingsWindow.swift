import AppKit
import AVFoundation
import CoachCore
import Speech

/// Real settings, in the same round style as the welcome window: which AI Pip uses and its key, how Pip moves, and
/// whether macOS has given F2L what it needs. Mirrors Windows/F2L.Windows/SettingsWindow.cs (which has no macOS
/// permissions section).
@MainActor
final class SettingsWindow: NSWindow, NSWindowDelegate, NSTextFieldDelegate {
    /// What Settings changes in Pip, supplied by the companion.
    struct Hooks {
        var reducedMotion: () -> Bool
        var setReducedMotion: (Bool) -> Void
        var followTargets: () -> Bool
        var setFollowTargets: (Bool) -> Void
        var resetPermissions: () -> Void
        var saveDiagnostics: () -> Void
    }

    private static let cream = Palette.hex(0xFAF8F3), sage = Palette.hex(0xE8EEE5), green = Palette.hex(0x345D50)
    private static let muted = Palette.hex(0x69736D), line = Palette.hex(0xE0E5DE), warn = Palette.hex(0x944C32)
    private static let width: CGFloat = 520
    private let root = FlippedView()
    private let body = FlippedView()
    private let scroll = NSScrollView()
    private let hooks: Hooks
    /// The provider whose key field is shown; starts as the one in use.
    private var selected = LocalSettings.provider()
    private var keyField: NSSecureTextField?
    private var notice = ""

    init(hooks: Hooks) {
        self.hooks = hooks
        let height = min(760, (NSScreen.main?.visibleFrame.height ?? 900) - 64)
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: height), styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = "F2L Settings"
        appearance = NSAppearance(named: .aqua)
        backgroundColor = Self.cream
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        delegate = self
        root.wantsLayer = true
        root.layer?.backgroundColor = Self.cream.cgColor
        contentView = root
        rebuild()
        center()
    }

    /// Permissions can change in System Settings while this is open: show what is true each time it comes forward.
    func windowDidBecomeKey(_ notification: Notification) { rebuild() }

    @discardableResult
    private func label(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 13, color: NSColor = Palette.ink,
                       weight: NSFont.Weight = .regular, in parent: NSView? = nil) -> CGFloat {
        let field = makeLabel(text, size: size, weight: weight, color: color, wraps: true)
        let height = ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 2000)).height ?? 18)
        field.frame = NSRect(x: x, y: y, width: width, height: height)
        (parent ?? body).addSubview(field)
        return height
    }

    @discardableResult
    private func button(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat? = nil, height: CGFloat = 34, selected: Bool = false,
                        in parent: NSView? = nil, action: @escaping () -> Void) -> FlatButton {
        let button = FlatButton(text, size: 12, ink: selected ? .white : Self.green, fill: selected ? Self.green : Self.sage)
        button.padding = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        if selected { button.weight = .semibold }
        let w = width ?? ceil(button.intrinsicContentSize.width)
        button.frame = NSRect(x: x, y: y, width: w, height: height)
        button.cornerRadius = height / 2
        button.onClick = action
        button.setAccessibilityLabel(text)
        (parent ?? body).addSubview(button)
        return button
    }

    private func card(y: CGFloat, height: CGFloat, width: CGFloat, fill: NSColor = .white, border: NSColor? = nil) -> RoundedBox {
        let box = RoundedBox(fill: fill, radius: min(26, height / 2), border: border ?? Self.line)
        box.frame = NSRect(x: 0, y: y, width: width, height: height)
        body.addSubview(box)
        return box
    }

    private func dot(_ on: Bool, at point: NSPoint, in parent: NSView) {
        let ring = RoundedBox(fill: on ? Self.green : .white, radius: 9, border: on ? nil : Palette.hex(0xCFD8CC))
        ring.frame = NSRect(origin: point, size: NSSize(width: 18, height: 18))
        parent.addSubview(ring)
        if on {
            let inner = RoundedBox(fill: .white, radius: 3.5)
            inner.frame = NSRect(x: 5.5, y: 5.5, width: 7, height: 7)
            ring.addSubview(inner)
        }
    }

    private func heading(_ text: String, _ y: CGFloat, width: CGFloat) -> CGFloat {
        y + label(text.uppercased(), x: 4, y: y, width: width, size: 11, color: Self.green, weight: .semibold) + 12
    }

    func rebuild() {
        let offset = scroll.contentView.bounds.origin
        let typed = keyField?.stringValue ?? ""
        root.subviews.forEach { $0.removeFromSuperview() }
        body.subviews.forEach { $0.removeFromSuperview() }
        let h = root.bounds.height, w = Self.width - 64
        _ = label("Settings", x: 32, y: 34, width: w - 70, size: 26, weight: .semibold, in: root)
        root.addSubview(BrandArtwork.view("Illustrations/settings-compass.png", frame: NSRect(x: Self.width - 92, y: 16, width: 60, height: 60)))
        scroll.frame = NSRect(x: 32, y: 82, width: w + 16, height: h - 82 - 74)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = body
        root.addSubview(scroll)
        body.frame = NSRect(x: 0, y: 0, width: w, height: 400)

        var y = providers(width: w, typed: typed)
        y = pip(y: y + 28, width: w)
        y = permissions(y: y + 28, width: w)
        y = privacy(y: y + 28, width: w)
        body.setFrameSize(NSSize(width: w, height: max(scroll.bounds.height, y + 12)))
        body.scroll(offset)

        let done = button("Done", x: Self.width - 32 - 110, y: h - 58, width: 110, height: 38, selected: true, in: root) { [weak self] in self?.close() }
        done.keyEquivalent = "\u{1b}"
    }

    // MARK: - AI

    private func providers(width: CGFloat, typed: String) -> CGFloat {
        var y = heading("Your AI", 0, width: width)
        y += label("Pip uses one AI at a time. Pick one, then paste its key. Keys stay in a private file on this Mac; Git ignores it and never uploads it.",
                   x: 4, y: y, width: width - 8, size: 12, color: Self.muted) + 14
        let current = LocalSettings.provider()
        for provider in Provider.allCases {
            let ready = !LocalSettings.read(provider.key).isEmpty
            let showing = provider == selected
            let row = card(y: y, height: 50, width: width, fill: showing ? Palette.hex(0xF1F6EF) : .white, border: showing ? Self.green : Self.line)
            dot(provider == current, at: NSPoint(x: 18, y: 16), in: row)
            _ = label(provider.name, x: 48, y: 15, width: 150, size: 14, weight: .semibold, in: row)
            _ = label(ready ? "Key added" : "No key yet", x: 170, y: 17, width: 120, size: 12,
                      color: ready ? Palette.verified : Self.muted, in: row)
            let tap = FlatButton(" ", size: 1, fill: nil)
            tap.frame = row.bounds
            tap.setAccessibilityLabel("\(provider.name), \(ready ? "key added" : "no key yet")")
            tap.onClick = { [weak self] in self?.selected = provider; self?.notice = ""; self?.rebuild() }
            row.addSubview(tap)
            if provider != current {
                button("Use", x: width - 86, y: 8, width: 70, in: row) { [weak self] in
                    LocalSettings.setProvider(provider)
                    self?.selected = provider
                    self?.notice = ready ? "Pip now uses \(provider.name)." : "Pip now uses \(provider.name). Paste its key below to start."
                    self?.rebuild()
                }
            } else {
                _ = label("In use", x: width - 80, y: 17, width: 64, size: 12, color: Self.green, weight: .semibold, in: row)
            }
            y += 58
        }
        y += 6
        let ready = !LocalSettings.read(selected.key).isEmpty
        y += label(ready ? "Replace your \(selected.name) key" : "Paste your \(selected.name) key",
                   x: 4, y: y, width: width, size: 13, weight: .semibold) + 8
        let box = card(y: y, height: 44, width: width - 112)
        let field = NSSecureTextField(string: typed)
        field.placeholderString = ready ? "Saved. Paste a new key to replace it" : "Your \(selected.name) API key"
        field.font = Fonts.inter(14); field.textColor = Palette.ink
        field.drawsBackground = false; field.isBordered = false; field.focusRingType = .none
        field.delegate = self
        field.setAccessibilityLabel("\(selected.name) API key")
        field.frame = NSRect(x: 20, y: 11, width: width - 152, height: 22)
        box.addSubview(field)
        keyField = field
        button("Save key", x: width - 102, y: y + 3, width: 102, height: 38, selected: true) { [weak self] in self?.saveKey() }
        y += 52
        if ready {
            let remove = button("Remove this key", x: 0, y: y, height: 28) { [weak self] in self?.removeKey() }
            remove.fill = nil
            y += 32
        }
        if !notice.isEmpty { y += label(notice, x: 4, y: y, width: width, size: 12, color: Self.green) + 4 }
        return y
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === keyField, selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        saveKey()
        return true
    }

    private func saveKey() {
        let value = keyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { notice = "Paste a key first."; rebuild(); return }
        keyField?.stringValue = ""
        if LocalSettings.setKey(selected.key, value) {
            LocalSettings.setProvider(selected)
            notice = "Saved. Pip now uses \(selected.name)."
        } else {
            notice = "The key couldn’t be saved. Check that this Mac’s F2L folder is writable, then try again."
        }
        rebuild()
    }

    private func removeKey() {
        keyField?.stringValue = ""
        notice = LocalSettings.setKey(selected.key, "") ? "\(selected.name)’s key was removed from this Mac." : "The key couldn’t be removed. Please try again."
        rebuild()
    }

    // MARK: - Pip

    private func pip(y start: CGFloat, width: CGFloat) -> CGFloat {
        var y = heading("Pip", start, width: width)
        for (index, (title, detail, on)) in [
            ("Reduce animation", "Words appear at once and Pip moves less.", hooks.reducedMotion()),
            ("Pip walks to what it’s teaching", "Off: Pip stays in its corner and circles the place instead.", hooks.followTargets()),
        ].enumerated() {
            let row = card(y: y, height: 62, width: width)
            _ = label(title, x: 20, y: 12, width: width - 110, size: 14, weight: .semibold, in: row)
            _ = label(detail, x: 20, y: 33, width: width - 110, size: 11, color: Self.muted, in: row)
            let toggle = NSSwitch(frame: NSRect(x: width - 62, y: 18, width: 42, height: 26))
            toggle.state = on ? .on : .off
            toggle.setAccessibilityLabel(title)
            toggle.tag = index
            toggle.target = self; toggle.action = #selector(switched(_:))
            row.addSubview(toggle)
            y += 70
        }
        return y
    }

    @objc private func switched(_ sender: NSSwitch) {
        (sender.tag == 0 ? hooks.setReducedMotion : hooks.setFollowTargets)(sender.state == .on)
    }

    // MARK: - Permissions

    private func permissions(y start: CGFloat, width: CGFloat) -> CGFloat {
        var y = heading("What macOS lets F2L do", start, width: width)
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        for (title, detail, allowed, pane) in [
            ("Screen Recording", "So Pip can see the app you ask about.", CGPreflightScreenCaptureAccess(), "Privacy_ScreenCapture"),
            ("Accessibility", "So Pip can find buttons and icons exactly.", AXIsProcessTrusted(), "Privacy_Accessibility"),
            ("Microphone", "Only when you speak a question.", speech, "Privacy_Microphone"),
        ] {
            let row = card(y: y, height: 62, width: width)
            _ = label(title, x: 20, y: 12, width: 220, size: 14, weight: .semibold, in: row)
            _ = label(detail, x: 20, y: 33, width: width - 190, size: 11, color: Self.muted, in: row)
            if allowed {
                _ = label("Allowed", x: width - 86, y: 22, width: 70, size: 12, color: Palette.verified, weight: .semibold, in: row)
            } else {
                button("Allow…", x: width - 96, y: 14, width: 80, in: row) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
            y += 70
        }
        y += label("Already allowed but macOS keeps asking? That happens when F2L was rebuilt without its signature. Reset, then allow F2L once more and reopen it.",
                   x: 4, y: y + 2, width: width - 8, size: 11, color: Self.muted) + 12
        button("Reset permissions", x: 0, y: y) { [weak self] in self?.hooks.resetPermissions(); self?.rebuild() }
        return y + 34
    }

    // MARK: - Privacy

    private func privacy(y start: CGFloat, width: CGFloat) -> CGFloat {
        var y = heading("Privacy and help", start, width: width)
        y += label("The latest 500 messages, your draft and your profile are saved on this Mac. Screenshots aren’t saved. Simple cell-pointing requests stay on this Mac; other questions and a picture of the app you ask about go to the AI you chose.",
                   x: 4, y: y, width: width - 8, size: 11, color: Self.muted) + 12
        let file = button("Show the settings file", x: 0, y: y) { NSWorkspace.shared.activateFileViewerSelecting([LocalSettings.prepareFile()]) }
        button("Save pointing diagnostics", x: file.frame.maxX + 8, y: y) { [weak self] in self?.hooks.saveDiagnostics() }
        return y + 34
    }
}
