import CoreGraphics
import Foundation

/// A second, zoomed look for a place F2L couldn't confirm from the screen's words or the app's controls (an icon-only
/// button such as Excel's Fill, or a button in an app the learner switched to). F2L crops the window around the AI's
/// first guess (or takes the whole window when there is none) and asks the same AI where the control is in that crop.
/// Cheap vision models shrink a whole window until small icons are a few pixels wide; a crop keeps them large.
/// Mirrors Windows/F2L.Windows/ZoomLocate.cs.
public enum ZoomLocate {
    public static let systemPrompt = """
        You find one control in a cropped screenshot of an app. Return only a JSON object.
        If the named control is clearly visible, return {"found":true,"left":L,"top":T,"right":R,"bottom":B} with integers
        from 0 to 1000 that are thousandths of this image and tightly surround the control.
        Otherwise return {"found":false}. Never guess.
        """

    public static func question(label: String, app: String) -> String {
        "Find the \"\(label)\" control (a button, tab, icon, menu item or field) in this part of the \(app) window. Its visible text may be in another language, or it may be an icon with that meaning. Return JSON."
    }

    /// Around the first guess: six times its size, at least 420 × 280 points, kept inside the window.
    public static let minimum = CGSize(width: 420, height: 280)

    public static func crop(around estimate: CGRect?, window: CGRect) -> CGRect {
        guard let estimate, !estimate.isEmpty, !window.isEmpty else { return window }
        let width = min(window.width, max(minimum.width, estimate.width * 6))
        let height = min(window.height, max(minimum.height, estimate.height * 6))
        let x = min(max(estimate.midX - width / 2, window.minX), window.maxX - width)
        let y = min(max(estimate.midY - height / 2, window.minY), window.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The crop in the picture's pixels, for a picture of `window` that is `pixels` wide and high.
    public static func pixelRect(_ crop: CGRect, window: CGRect, pixels: CGSize) -> CGRect {
        guard window.width > 0, window.height > 0 else { return .zero }
        let sx = pixels.width / window.width, sy = pixels.height / window.height
        return CGRect(x: (crop.minX - window.minX) * sx, y: (crop.minY - window.minY) * sy, width: crop.width * sx, height: crop.height * sy)
            .integral.intersection(CGRect(origin: .zero, size: pixels))
    }

    /// The control's place on screen from the reply, or nil when it wasn't found or the box makes no sense.
    public static func parse(_ text: String, crop: CGRect) -> CGRect? {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = CoachClient.fenceStart.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
            clean = CoachClient.fenceEnd.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(clean.utf8))) as? [String: Any],
              object["found"] as? Bool == true else { return nil }
        func value(_ key: String) -> CGFloat? {
            guard let number = object[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), (0...1000).contains(number.doubleValue) else { return nil }
            return CGFloat(number.doubleValue) / 1000
        }
        guard let left = value("left"), let top = value("top"), let right = value("right"), let bottom = value("bottom"),
              right > left, bottom > top else { return nil }
        let box = CGRect(x: crop.minX + left * crop.width, y: crop.minY + top * crop.height,
                         width: (right - left) * crop.width, height: (bottom - top) * crop.height)
        // A control is small: a box over most of the crop means the model didn't really find it.
        guard box.width >= 4, box.height >= 4, box.width <= crop.width * 0.8, box.height <= crop.height * 0.8 else { return nil }
        return box
    }
}

extension CoachClient {
    /// Asks the chosen AI where `label` is in `jpeg`, a crop of the learner's window covering `crop` on screen. Nil when
    /// there is no key, the reply can't be read, or the control isn't there. One short request (about 80 output tokens).
    public func zoomLocate(label: String, app: String, jpeg: Data, crop: CGRect) async -> CGRect? {
        let current = settings()
        guard !current.apiKey.isEmpty, !jpeg.isEmpty else { return nil }
        guard let data = try? await response(current, question: ZoomLocate.question(label: label, app: app), history: [], jpeg: jpeg,
                                             jsonMode: true, systemPrompt: ZoomLocate.systemPrompt, maxTokens: 80),
              let text = try? Self.responseText(data, provider: current.provider) else { return nil }
        return ZoomLocate.parse(text, crop: crop)
    }
}
