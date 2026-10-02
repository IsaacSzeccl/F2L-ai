import CoreGraphics
import Foundation

/// A JSON-schema tool definition, provider-neutral.
public struct ToolDefinition: Sendable {
    public var name: String
    public var description: String
    /// JSON Schema for the arguments, already serialized.
    public var parametersJSON: String

    public var parameters: Any {
        (try? JSONSerialization.jsonObject(with: Data(parametersJSON.utf8))) ?? [String: Any]()
    }
}

/// What the model asked the overlay to do.
public enum PointerCommand: Sendable, Equatable {
    /// Point at an Accessibility element by its id from the element list.
    case element(id: String, caption: String?)
    /// Vision fallback: a box in 0–1000 normalized coordinates of the screenshot, [x1, y1, x2, y2].
    case region(box: [Double], caption: String?)
    case clear
}

public enum AnnotationStyle: String, Sendable, Equatable {
    /// Exact AX frame: solid ring + arrow.
    case precise
    /// Vision guess: dashed, larger ring labelled "around here". Never drawn as if certain.
    case approximate
}

/// A resolved annotation, ready to draw. `rect` is global, top-left origin.
public struct Annotation: Sendable, Equatable {
    public var rect: CGRect
    public var style: AnnotationStyle
    public var caption: String?
    /// AX element id when precise; used by the step watcher.
    public var elementID: String?
    public var elementRole: String?

    public init(rect: CGRect, style: AnnotationStyle, caption: String?, elementID: String? = nil, elementRole: String? = nil) {
        self.rect = rect
        self.style = style
        self.caption = caption
        self.elementID = elementID
        self.elementRole = elementRole
    }
}

public enum CoachTools {
    public static let pointAt = "point_at"
    public static let pointAtRegion = "point_at_region"
    public static let clearPointer = "clear_pointer"

    public static let all: [ToolDefinition] = [
        ToolDefinition(
            name: pointAt,
            description: """
            Circle one on-screen control for the learner. Use the element id from the ON-SCREEN CONTROLS list \
            (for example "e12"). Only ids from that list are valid. Call this whenever you tell the learner to \
            click, type into, or look at a specific control.
            """,
            parametersJSON: """
            {"type":"object","properties":{\
            "element_id":{"type":"string","description":"An id from the ON-SCREEN CONTROLS list, e.g. e12"},\
            "caption":{"type":"string","description":"2-5 word label shown next to the circle, e.g. 'Type your question here'"}\
            },"required":["element_id"]}
            """
        ),
        ToolDefinition(
            name: pointAtRegion,
            description: """
            Fallback ONLY when the thing you need is visible in the screenshot but is not in the ON-SCREEN CONTROLS \
            list. Give a bounding box in 0-1000 normalized screenshot coordinates. This is drawn as an approximate \
            "around here" marker, so also describe the spot in words.
            """,
            parametersJSON: """
            {"type":"object","properties":{\
            "box":{"type":"array","items":{"type":"number"},"minItems":4,"maxItems":4,\
            "description":"[x1, y1, x2, y2], each 0-1000, relative to the screenshot"},\
            "caption":{"type":"string","description":"2-5 word label"}\
            },"required":["box"]}
            """
        ),
        ToolDefinition(
            name: clearPointer,
            description: "Remove the current circle when it is no longer relevant.",
            parametersJSON: #"{"type":"object","properties":{}}"#
        ),
    ]

    /// Parses a tool call into a command. Returns nil for unknown tools or malformed arguments.
    public static func parse(_ call: ToolCall) -> PointerCommand? {
        let args = (try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8))) as? [String: Any] ?? [:]
        let caption = (args["caption"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        switch call.name {
        case pointAt:
            guard let id = args["element_id"] as? String, !id.isEmpty else { return nil }
            return .element(id: id.trimmingCharacters(in: .whitespaces), caption: caption)
        case pointAtRegion:
            guard let raw = args["box"] as? [Any] else { return nil }
            let box = raw.compactMap { ($0 as? NSNumber)?.doubleValue }
            guard box.count == 4 else { return nil }
            return .region(box: box, caption: caption)
        case clearPointer:
            return .clear
        default:
            return nil
        }
    }

    /// Turns a command into a drawable annotation against the current screen.
    /// An element id that isn't in the context resolves to nil: the coach can never point at
    /// something that isn't on screen.
    public static func resolve(_ command: PointerCommand, in context: ScreenContext) -> Annotation? {
        switch command {
        case .clear:
            return nil
        case let .element(id, caption):
            guard let element = context.element(withID: id) else { return nil }
            return Annotation(rect: element.frame, style: .precise, caption: caption, elementID: id, elementRole: element.role)
        case let .region(box, caption):
            guard let rect = Geometry.normalizedBoxToGlobal(box, windowFrame: context.windowFrame) else { return nil }
            return Annotation(rect: rect, style: .approximate, caption: caption ?? "Around here")
        }
    }
}
