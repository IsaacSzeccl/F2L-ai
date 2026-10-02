import CoreGraphics
import Foundation

/// Something the learner did to the control the coach circled, worth a proactive nudge.
public enum StepEvent: Sendable, Equatable {
    /// Typed into the circled text box and paused.
    case typed(label: String, preview: String)
    /// The circled text box went from filled to empty (message sent).
    case submitted(label: String)
    /// Clicked inside the circled control.
    case clicked(label: String)

    public var description: String {
        switch self {
        case let .typed(label, preview): "The learner typed into \"\(label)\" and paused. It now says: \"\(preview)\""
        case let .submitted(label): "The text in \"\(label)\" was sent (the box is empty again)."
        case let .clicked(label): "The learner clicked \"\(label)\", the control you circled."
        }
    }
}

/// Watches the one control the coach is pointing at and reports when the learner acts on it.
/// Pure state machine: the app feeds it AX values, mouse clicks and clock ticks.
public struct StepTracker: Sendable {
    public enum Kind: Sendable, Equatable { case textEntry, clickable }

    public let label: String
    public let kind: Kind
    public private(set) var frame: CGRect
    /// How long typing must pause before it counts as "typed".
    public var typingPause: TimeInterval

    private var lastValue: String
    private var lastChange: Date?
    private var reportedTypedValue: String?
    private var finished = false

    public static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]

    public init(label: String, role: String, frame: CGRect, initialValue: String = "", typingPause: TimeInterval = 1.5) {
        self.label = label
        self.kind = Self.textRoles.contains(role) ? .textEntry : .clickable
        self.frame = frame
        self.typingPause = typingPause
        self.lastValue = initialValue
    }

    public var isFinished: Bool { finished }

    /// The control moved (scroll, window drag): clicks are matched against its new frame.
    public mutating func move(to frame: CGRect) {
        self.frame = frame
    }

    public mutating func observe(value: String, at now: Date) -> StepEvent? {
        guard !finished, kind == .textEntry, value != lastValue else { return nil }
        let wasFilled = !lastValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        lastValue = value
        lastChange = now
        if wasFilled && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finished = true
            return .submitted(label: label)
        }
        return nil
    }

    public mutating func tick(at now: Date) -> StepEvent? {
        guard !finished, kind == .textEntry, let lastChange, now.timeIntervalSince(lastChange) >= typingPause else { return nil }
        let trimmed = lastValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, reportedTypedValue != lastValue else { return nil }
        reportedTypedValue = lastValue
        return .typed(label: label, preview: String(trimmed.prefix(200)))
    }

    /// `point` is global, top-left origin (same space as `frame`).
    public mutating func observeClick(at point: CGPoint) -> StepEvent? {
        guard !finished, kind == .clickable, frame.insetBy(dx: -6, dy: -6).contains(point) else { return nil }
        finished = true
        return .clicked(label: label)
    }
}
