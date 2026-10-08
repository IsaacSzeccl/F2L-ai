import AppKit
import ApplicationServices
import CoachCore

/// Read-only Accessibility queries, the Mac counterpart of the Win32 calls in NativeDesktop.cs.
/// macOS only answers them once F2L is allowed under Privacy & Security › Accessibility.
enum DesktopAccessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt, which opens the Accessibility list in System Settings.
    static func requestTrust() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func rect(_ value: AnyObject?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.null
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    /// The text caret of the focused control in another app, in global top-left points, like
    /// NativeDesktop.ActiveCaretBounds. Nil when there is no caret or the app doesn't report one.
    static func caretBounds(timeout: Float = 0.1) -> CGRect? {
        guard isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        guard let focused = attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        guard let selection = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(selection) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(selection as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }
        // The insertion point is the start of the selection.
        var insertion = CFRange(location: range.location, length: 0)
        guard let parameter = AXValueCreate(.cfRange, &insertion) else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
              let bounds = rect(value), bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds != .zero, bounds.height > 0, bounds.height < 400, bounds.width < 400 else { return nil }
        return CGRect(x: bounds.minX, y: bounds.minY, width: max(2, bounds.width), height: max(2, bounds.height))
    }
}

extension DesktopAccessibility {
    /// Roles that are things a learner clicks or reads as a label.
    static let controlRoles: Set<String> = ["AXButton", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton", "AXMenuBarItem",
                                            "AXMenuItem", "AXTab", "AXComboBox", "AXTextField", "AXLink", "AXDisclosureTriangle",
                                            "AXSegmentedControl", "AXSlider", "AXStaticText", "AXImage"]

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// The named controls of app `pid` that are inside `window` (or in its menu bar), global top-left points.
    /// Read-only, bounded in time and size; empty without the Accessibility permission. Call off the main thread.
    static func controls(pid: pid_t, in window: CGRect, limit: Int = 4000, timeout: Float = 0.2) -> [ControlCandidate] {
        guard isTrusted else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var found: [ControlCandidate] = []
        var stack: [(AXUIElement, Int)] = [(app, 0)]
        var visited = 0
        let started = Date()
        while let (element, depth) = stack.popLast(), visited < limit, Date().timeIntervalSince(started) < 1.5 {
            visited += 1
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if controlRoles.contains(role), let frame = frame(element), frame.intersects(window) || role == "AXMenuBarItem" {
                let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] + (role == "AXStaticText" ? [kAXValueAttribute] : [])
                if let name = names.lazy.compactMap({ attribute(element, $0) as? String }).first(where: { !$0.isEmpty }) {
                    found.append(ControlCandidate(frame: frame, name: name))
                }
            }
            // The worksheet grid has nothing to name; skipping it keeps Excel fast.
            guard depth < 18, role != "AXLayoutArea", let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
        }
        return found
    }

    /// The biggest element with `role` inside `window`, such as Excel's worksheet grid (AXLayoutArea).
    static func largest(role wanted: String, pid: pid_t, in window: CGRect, limit: Int = 3000, timeout: Float = 0.2) -> CGRect? {
        guard isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        var best: CGRect?
        var stack: [(AXUIElement, Int)] = [(app, 0)]
        var visited = 0
        while let (element, depth) = stack.popLast(), visited < limit {
            visited += 1
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if role == wanted, let frame = frame(element), frame.intersects(window), frame.width * frame.height > (best.map { $0.width * $0.height } ?? 0) {
                best = frame
            }
            guard depth < 18, role != wanted, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
        }
        return best
    }
}

/// Polls the caret off the main thread while Pip is teaching, so a slow or hung app never stalls Pip's animation.
final class CaretTracker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ai.f2l.companion.caret", qos: .userInitiated)
    private let lock = NSLock()
    private var latest: CGRect?
    private var timer: DispatchSourceTimer?

    var caret: CGRect? { lock.withLock { latest } }

    func start() {
        guard timer == nil, DesktopAccessibility.isTrusted else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            let caret = DesktopAccessibility.caretBounds()
            self?.lock.withLock { self?.latest = caret }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        lock.withLock { latest = nil }
    }

    deinit { timer?.cancel() }
}
