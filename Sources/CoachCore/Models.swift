import CoreGraphics
import Foundation

/// One interactive control on screen, read from the macOS Accessibility tree.
/// `frame` is in global screen coordinates with a TOP-LEFT origin (the AX convention).
public struct ScreenElement: Codable, Sendable, Equatable {
    public var id: String
    public var role: String
    public var label: String
    public var frame: CGRect

    public init(id: String, role: String, label: String, frame: CGRect) {
        self.id = id
        self.role = role
        self.label = label
        self.frame = frame
    }
}

/// A JPEG screenshot of the front window, held in memory only.
public struct ImageAttachment: Codable, Sendable, Equatable {
    public var jpegBase64: String
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(jpegBase64: String, pixelWidth: Int, pixelHeight: Int) {
        self.jpegBase64 = jpegBase64
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var dataURL: String { "data:image/jpeg;base64,\(jpegBase64)" }
}

/// Everything the coach knows about the learner's screen for one turn.
public struct ScreenContext: Codable, Sendable, Equatable {
    public var appName: String
    public var windowTitle: String
    /// Front window frame, global coordinates, top-left origin. The screenshot covers exactly this rect.
    public var windowFrame: CGRect
    public var elements: [ScreenElement]
    /// One-line description from the background vision loop, if any.
    public var summary: String?
    public var screenshot: ImageAttachment?

    public init(
        appName: String,
        windowTitle: String,
        windowFrame: CGRect,
        elements: [ScreenElement],
        summary: String? = nil,
        screenshot: ImageAttachment? = nil
    ) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.windowFrame = windowFrame
        self.elements = elements
        self.summary = summary
        self.screenshot = screenshot
    }

    public func element(withID id: String) -> ScreenElement? {
        elements.first { $0.id == id }
    }
}

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant
}

public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: ChatRole
    public var text: String
    public var image: ImageAttachment?

    public init(role: ChatRole, text: String, image: ImageAttachment? = nil) {
        self.role = role
        self.text = text
        self.image = image
    }
}

public struct ToolCall: Sendable, Equatable {
    public var id: String
    public var name: String
    public var argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public enum LLMEvent: Sendable, Equatable {
    case text(String)
    case toolCall(ToolCall)
}
