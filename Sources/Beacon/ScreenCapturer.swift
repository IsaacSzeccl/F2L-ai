import AppKit
import CoachCore
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Captures a single window (never the whole display) into an in-memory JPEG.
enum ScreenCapturer {
    /// Longest side sent to the model. Bigger costs latency; smaller loses small icons.
    static let maxDimension = 1440

    struct Capture {
        var image: ImageAttachment
        /// The captured window's frame, global top-left origin. Normalized model boxes map onto this.
        var windowFrame: CGRect
    }

    static func captureFrontWindow(pid: pid_t, near axFrame: CGRect) async throws -> Capture? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let candidates = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40
        }
        guard let window = bestMatch(candidates, for: axFrame) else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Native pixels per point of the display the window is on (2 on Retina, 1 on most external screens).
        let pixelScale = max(1, Double(SCShareableContent.info(for: filter).pointPixelScale))
        let nativeLongSide = Double(max(window.frame.width, window.frame.height)) * pixelScale
        let scale = min(1, Double(maxDimension) / nativeLongSide) * pixelScale
        config.width = max(1, Int(Double(window.frame.width) * scale))
        config.height = max(1, Int(Double(window.frame.height) * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let jpeg = jpegData(cgImage) else { return nil }
        let attachment = ImageAttachment(jpegBase64: jpeg.base64EncodedString(), pixelWidth: cgImage.width, pixelHeight: cgImage.height)
        return Capture(image: attachment, windowFrame: window.frame)
    }

    /// The window whose frame best overlaps the AX focused window (SCWindow.frame is top-left global, like AX).
    private static func bestMatch(_ windows: [SCWindow], for axFrame: CGRect) -> SCWindow? {
        guard !axFrame.isEmpty else { return windows.first }
        return windows.max { a, b in overlap(a.frame, axFrame) < overlap(b.frame, axFrame) }
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.65) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
