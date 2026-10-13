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
    /// The length and a hash of the text in the focused box of the app in front, so a typing step can tick without
    /// F2L keeping what was typed. Nil without permission or when no text box has focus. Call off the main thread.
    static func focusedTextFingerprint() -> TypingWatch.Fingerprint? {
        guard isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard let focused = attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        // Typing into Pip's own question box is not the step.
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier,
              let value = attribute(element, kAXValueAttribute) as? String else { return nil }
        return TypingWatch.Fingerprint(length: value.count, hash: value.hashValue)
    }

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
    /// Everything a walk needs from one element, asked for in a single round trip to the app (about twice as fast as
    /// one attribute at a time).
    private static let walkAttributes = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute,
                                         kAXDescriptionAttribute, kAXHelpAttribute, kAXChildrenAttribute] as CFArray
    /// Containers whose contents are skipped when they lie outside the window: content scrolled away, other windows.
    static let prunable: Set<String> = ["AXWindow", "AXGroup", "AXScrollArea", "AXList", "AXTable", "AXOutline", "AXRow",
                                        "AXWebArea", "AXSplitGroup", "AXTabGroup", "AXBrowser", "AXSheet", "AXDrawer"]

    static func frame(position: AnyObject, size: AnyObject) -> CGRect? {
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// Walks app `pid`'s accessibility tree, calling `visit` with each element's role and frame (and its values), and
    /// stops after `limit` elements or `budget` seconds. Branches outside `window` are not entered.
    private static func walk(pid: pid_t, in window: CGRect, limit: Int, timeout: Float, budget: TimeInterval,
                             skip: Set<String> = [], visit: (AXUIElement, String, CGRect?, [AnyObject]) -> Void) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        // Electron apps (Notion, Slack, VS Code…) only build their tree when asked; others ignore this.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var stack: [(AXUIElement, Int)] = [(app, 0)]
        var visited = 0
        let started = Date()
        while let (element, depth) = stack.popLast(), visited < limit, Date().timeIntervalSince(started) < budget {
            visited += 1
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, walkAttributes, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
                  let values = raw as? [AnyObject], values.count == 7 else { continue }
            let role = values[0] as? String ?? ""
            let frame = Self.frame(position: values[1], size: values[2])
            visit(element, role, frame, values)
            if let frame, frame.width > 0, frame.height > 0, !frame.intersects(window), prunable.contains(role) { continue }
            guard depth < 18, !skip.contains(role), let children = values[6] as? [AXUIElement] else { continue }
            stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
        }
    }

    /// The named controls of app `pid` that are inside `window` (or in its menu bar), global top-left points.
    /// Read-only, bounded in time and size; empty without the Accessibility permission. Call off the main thread.
    static func controls(pid: pid_t, in window: CGRect, limit: Int = 4000, timeout: Float = 0.2, budget: TimeInterval = 1.5) -> [ControlCandidate] {
        guard isTrusted else { return [] }
        var found: [ControlCandidate] = []
        // The worksheet grid has nothing to name; skipping it keeps Excel fast.
        walk(pid: pid, in: window, limit: limit, timeout: timeout, budget: budget, skip: ["AXLayoutArea"]) { element, role, frame, values in
            guard controlRoles.contains(role), let frame, frame.intersects(window) || role == "AXMenuBarItem" else { return }
            let text = [3, 4, 5].lazy.compactMap { values[$0] as? String }.first { !$0.isEmpty }
            // A static text's words are its value; asked for only here, since a text area's value can be a whole document.
            if let name = text ?? (role == "AXStaticText" ? attribute(element, kAXValueAttribute) as? String : nil), !name.isEmpty {
                found.append(ControlCandidate(frame: frame, name: name))
            }
        }
        return found
    }

    /// The biggest element with `role` inside `window`, such as Excel's worksheet grid (AXLayoutArea).
    static func largest(role wanted: String, pid: pid_t, in window: CGRect, limit: Int = 3000, timeout: Float = 0.2) -> CGRect? {
        guard isTrusted else { return nil }
        var best: CGRect?
        walk(pid: pid, in: window, limit: limit, timeout: timeout, budget: 1.5, skip: [wanted]) { _, role, frame, _ in
            if role == wanted, let frame, frame.intersects(window), frame.width * frame.height > (best.map { $0.width * $0.height } ?? 0) {
                best = frame
            }
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
