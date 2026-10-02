import CoreGraphics

public enum Geometry {
    /// Maps a [x1, y1, x2, y2] box in 0–1000 screenshot coordinates onto the window it was taken of.
    /// Swapped corners are tolerated; out-of-range values are clamped. Returns nil for empty boxes.
    public static func normalizedBoxToGlobal(_ box: [Double], windowFrame: CGRect) -> CGRect? {
        guard box.count == 4, windowFrame.width > 0, windowFrame.height > 0 else { return nil }
        let clamp = { (v: Double) in min(max(v, 0), 1000) / 1000 }
        let x1 = clamp(min(box[0], box[2])), x2 = clamp(max(box[0], box[2]))
        let y1 = clamp(min(box[1], box[3])), y2 = clamp(max(box[1], box[3]))
        guard x2 > x1, y2 > y1 else { return nil }
        return CGRect(
            x: windowFrame.minX + x1 * windowFrame.width,
            y: windowFrame.minY + y1 * windowFrame.height,
            width: (x2 - x1) * windowFrame.width,
            height: (y2 - y1) * windowFrame.height
        )
    }

    /// Converts a global top-left-origin rect (Accessibility, CoreGraphics window list) into
    /// AppKit's global bottom-left-origin space. `primaryScreenHeight` is the height of the
    /// screen whose origin is (0, 0) in AppKit (NSScreen.screens[0]).
    public static func topLeftToAppKit(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Ring drawn around a target: padded, and never smaller than `minSide` so tiny icons stay visible.
    public static func ringRect(for target: CGRect, padding: CGFloat = 8, minSide: CGFloat = 36) -> CGRect {
        var r = target.insetBy(dx: -padding, dy: -padding)
        if r.width < minSide { r = r.insetBy(dx: -(minSide - r.width) / 2, dy: 0) }
        if r.height < minSide { r = r.insetBy(dx: 0, dy: -(minSide - r.height) / 2) }
        return r
    }
}
