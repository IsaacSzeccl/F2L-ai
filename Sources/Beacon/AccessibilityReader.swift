import AppKit
@preconcurrency import ApplicationServices
import CoachCore

/// A snapshot of the learner's front window from the Accessibility tree.
struct AXSnapshot {
    var pid: pid_t
    var appName: String
    var windowTitle: String
    /// Global, top-left origin.
    var windowFrame: CGRect
    var elements: [ScreenElement]
    /// Live references for each element id, so the step watcher can follow the circled control.
    var references: [String: AXUIElement]
    /// A password box has keyboard focus: no screenshot may be taken.
    var secureFieldFocused: Bool

    static let empty = AXSnapshot(pid: 0, appName: "", windowTitle: "", windowFrame: .zero, elements: [], references: [:], secureFieldFocused: false)
}

/// Reads interactive controls from the front window. All AX calls run on a private serial queue:
/// they are synchronous IPC and a slow app must never stall the UI.
final class AccessibilityReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.beacon.ax", qos: .userInitiated)
    private var enabledWebAccessibility = Set<pid_t>()

    static let interactiveRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXComboBox", "AXPopUpButton", "AXMenuButton",
        "AXMenuItem", "AXLink", "AXCheckBox", "AXRadioButton", "AXSlider", "AXDisclosureTriangle",
        "AXIncrementor", "AXColorWell",
    ]

    private let maxVisited = 5000
    private let maxElements = 300
    private let maxDepth = 60
    /// Hard budget for one tree walk; whatever was found by then is used.
    private let walkBudget: TimeInterval = 0.7

    init() {
        // Applies to every element: a busy app (Chrome mid-render) must not block a call for the 6 s default.
        // 0.5 s leaves room for Chrome's first tree build after web accessibility is switched on.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
    }

    func snapshot(of app: NSRunningApplication) async -> AXSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.readSnapshot(app))
            }
        }
    }

    /// Chrome and Electron apps only build their web accessibility tree once an assistive client asks.
    /// Call this as soon as an app comes to the front so the tree is ready by the time the learner speaks.
    func prepare(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        queue.async {
            guard !self.enabledWebAccessibility.contains(pid) else { return }
            self.enabledWebAccessibility.insert(pid)
            let element = AXUIElementCreateApplication(pid)
            let manual = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if manual != .success, Self.isChromium(app) {
                // Older Chromium builds only honour this one. It can disturb window-manager animations.
                _ = AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }
    }

    struct ElementState {
        var frame: CGRect?
        var value: String?
        /// The element no longer exists (page changed). A nil frame without this is just a slow read.
        var gone: Bool
    }

    /// Current frame and value of one element (for following the circled control).
    func state(of element: AXUIElement) async -> ElementState {
        await withCheckedContinuation { continuation in
            queue.async {
                var role: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
                let gone = status == .invalidUIElement
                continuation.resume(returning: ElementState(
                    frame: gone ? nil : Self.frame(of: element),
                    value: gone ? nil : Self.string(element, kAXValueAttribute),
                    gone: gone
                ))
            }
        }
    }

    /// Cheap pre-capture check: is a password box focused, and where is the front window?
    func secureFocusAndFrame(of app: NSRunningApplication) async -> (secure: Bool, windowFrame: CGRect) {
        await withCheckedContinuation { continuation in
            queue.async {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                let frame = Self.focusedWindow(appElement).flatMap(Self.frame(of:)) ?? .zero
                continuation.resume(returning: (Self.isSecureFocused(appElement), frame))
            }
        }
    }

    /// Title of the front window only: a cheap signature for "has the screen changed?".
    func windowSignature(of app: NSRunningApplication) async -> String {
        await withCheckedContinuation { continuation in
            queue.async {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                let title = Self.focusedWindow(appElement).flatMap { Self.string($0, kAXTitleAttribute) } ?? ""
                continuation.resume(returning: "\(app.processIdentifier)|\(title)")
            }
        }
    }

    // MARK: - Tree walk

    private func readSnapshot(_ app: NSRunningApplication) -> AXSnapshot {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let deadline = Date().addingTimeInterval(walkBudget)

        var snapshot = AXSnapshot.empty
        snapshot.pid = pid
        snapshot.appName = app.localizedName ?? "Unknown app"
        snapshot.secureFieldFocused = Self.isSecureFocused(appElement)

        guard let window = Self.focusedWindow(appElement) else { return snapshot }
        snapshot.windowTitle = Self.string(window, kAXTitleAttribute) ?? ""
        snapshot.windowFrame = Self.frame(of: window) ?? .zero
        let visibleArea = snapshot.windowFrame

        let focused = Self.element(appElement, kAXFocusedUIElementAttribute)
        var found: [(element: AXUIElement, role: String, label: String, frame: CGRect, priority: Int)] = []
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var head = 0
        var visited = 0
        // The focused control (usually the box the learner is typing in) goes in first, so neither the time
        // budget nor the element cap can drop it.
        if let focused, let frame = Self.frame(of: focused), frame.width >= 2, frame.height >= 2,
           Self.string(focused, kAXSubroleAttribute) != "AXSecureTextField" {
            let role = Self.string(focused, kAXRoleAttribute) ?? ""
            if Self.isInteractive(focused, role: role) {
                let label = Self.label(for: focused, role: role)
                found.append((focused, role, label.isEmpty ? "(unlabelled \(PromptBuilder.humanRole(role)))" : label, frame, 0))
            }
        }

        while head < queue.count, visited < maxVisited, found.count < maxElements {
            if Date() > deadline {
                Log.screen.info("AX walk hit its time budget after \(visited) nodes")
                break
            }
            let (element, depth) = queue[head]
            head += 1
            visited += 1

            let role = Self.string(element, kAXRoleAttribute) ?? ""
            let subrole = Self.string(element, kAXSubroleAttribute) ?? ""

            if subrole == "AXSecureTextField" { continue } // never list password boxes

            let frame = Self.frame(of: element)
            // Anything entirely outside the window (scrolled away) can't be clicked: skip its subtree too.
            if let frame, !visibleArea.isEmpty, frame.width > 0, frame.height > 0, !visibleArea.intersects(frame) { continue }

            if let frame, frame.width >= 2, frame.height >= 2, Self.isInteractive(element, role: role) {
                let label = Self.label(for: element, role: role)
                if !label.isEmpty || Self.textRoles.contains(role) {
                    let effectiveRole = subrole == "AXSearchField" ? "AXSearchField" : role
                    let isFocused = focused.map { CFEqual($0, element) } ?? false
                    if isFocused { continue } // already added up front
                    // Input boxes and the focused control first, so they survive the prompt's element cap.
                    let priority = isFocused ? 0 : (Self.textRoles.contains(role) ? 1 : 2)
                    found.append((element, effectiveRole, label.isEmpty ? "(unlabelled \(PromptBuilder.humanRole(role)))" : label, frame, priority))
                }
            }

            guard depth < maxDepth else { continue }
            for child in Self.children(of: element) {
                queue.append((child, depth + 1))
            }
        }
        // Stable sort: by priority, then reading order from the walk.
        let ordered = found.enumerated().sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }
        for (index, item) in ordered.enumerated() {
            let id = "e\(index + 1)"
            snapshot.elements.append(ScreenElement(id: id, role: item.element.role, label: item.element.label, frame: item.element.frame))
            snapshot.references[id] = item.element.element
        }
        return snapshot
    }

    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    private static func isInteractive(_ element: AXUIElement, role: String) -> Bool {
        if interactiveRoles.contains(role) { return true }
        // Web apps render many clickable things as generic groups; trust an explicit press action.
        guard role == "AXGroup" || role == "AXImage" || role == "AXCell" else { return false }
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success, let names = actions as? [String] else { return false }
        return names.contains(kAXPressAction as String)
    }

    private static func label(for element: AXUIElement, role: String) -> String {
        var parts: [String] = []
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue" as String, kAXHelpAttribute] {
            if let value = string(element, attribute), !value.isEmpty, !parts.contains(value) {
                parts.append(value)
            }
            if parts.count >= 2 { break }
        }
        if parts.isEmpty, !textRoles.contains(role) {
            // Buttons in web pages often carry their text in a child.
            for child in children(of: element).prefix(4) {
                if let text = string(child, kAXValueAttribute) ?? string(child, kAXTitleAttribute), !text.isEmpty {
                    parts.append(text)
                    break
                }
            }
        }
        if textRoles.contains(role), let value = string(element, kAXValueAttribute), !value.isEmpty {
            parts.append("currently contains: \"\(value.prefix(60))\"")
        }
        return parts.joined(separator: " — ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AX helpers

    static func focusedWindow(_ app: AXUIElement) -> AXUIElement? {
        if let w = element(app, kAXFocusedWindowAttribute) { return w }
        if let w = element(app, kAXMainWindowAttribute) { return w }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first
    }

    /// Fails closed: if the app is too busy to say what has focus, treat it as a password box.
    static func isSecureFocused(_ app: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
        if status == .cannotComplete { return true }
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        var subrole: CFTypeRef?
        let subroleStatus = AXUIElementCopyAttributeValue(value as! AXUIElement, kAXSubroleAttribute as CFString, &subrole)
        if subroleStatus == .cannotComplete { return true }
        return (subrole as? String) == "AXSecureTextField"
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let a = value as? NSAttributedString { return a.string.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private static func isChromium(_ app: NSRunningApplication) -> Bool {
        let id = app.bundleIdentifier ?? ""
        return ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser"].contains(id)
    }
}
