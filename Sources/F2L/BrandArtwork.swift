import AppKit
import ImageIO

/// F2L's original painted artwork (Assets/Brand and Assets/Illustrations, shared with Windows), decoded once at the
/// size it is shown and reused across the opening, the welcome window and Settings. The masters are 1254 px squares;
/// keeping them at full size would hold about 6 MB each, so squares are decoded at most 512 px (sharp up to 256
/// points on a Retina screen). Mirrors Windows/F2L.Windows/BrandArtwork.cs.
@MainActor
enum BrandArtwork {
    /// Every picture the app shows, checked by `F2L --render`.
    static let paths = ["Brand/learning-doorway.png", "Brand/launch-landscape.png",
                        "Illustrations/your-work.png", "Illustrations/your-pace.png", "Illustrations/your-plan.png",
                        "Illustrations/first-spark.png", "Illustrations/exploring.png", "Illustrations/daily-practice.png",
                        "Illustrations/settings-compass.png"]
    /// The opening's backdrop fills the screen, so it keeps its full 1672 px width.
    static let landscape = "Brand/launch-landscape.png"
    private static let squareLimit = 512
    private static var cache: [String: CGImage] = [:]

    /// The picture as a CGImage (for layers), decoded once.
    static func cgImage(_ path: String) -> CGImage? {
        if let image = cache[path] { return image }
        guard let url = Assets.url(path), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceThumbnailMaxPixelSize: path == landscape ? 1672 : squareLimit]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache[path] = image
        return image
    }

    /// The picture as an NSImage (for drawing and image views).
    static func image(_ path: String) -> NSImage? {
        cgImage(path).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    /// Lets a picture that is only shown once (the opening's backdrop) be freed.
    static func forget(_ path: String) { cache[path] = nil }

    static func view(_ path: String, frame: NSRect) -> NSImageView {
        let view = NSImageView(frame: frame)
        view.image = image(path)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityElement(false) // Decorative; adjacent native labels carry the meaning.
        return view
    }
}
