// Render a review catalog using the actual original assets; native labels stay outside the artwork.
// Run from the repository root: swift scripts/tools/preview_brand.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Windows/F2L.Windows/Assets")
let items = [
    ("Brand/learning-doorway.png", "01  Learning doorway", "Launch emblem + setup signature"),
    ("Brand/app-icon.png", "02  App icon", "macOS .icns + Windows .ico"),
    ("Brand/launch-landscape.png", "03  Dusk learning landscape", "Animated entry screen backdrop"),
    ("Illustrations/your-work.png", "04  Your work", "Setup / work and goals"),
    ("Illustrations/your-pace.png", "05  Your pace", "Setup / learning experience"),
    ("Illustrations/your-plan.png", "06  Your plan", "Setup / personal learning path"),
    ("Illustrations/first-spark.png", "07  First spark", "Just getting started"),
    ("Illustrations/exploring.png", "08  Exploring", "Tried a few things"),
    ("Illustrations/daily-practice.png", "09  Daily practice", "Part of my routine"),
    ("Illustrations/settings-compass.png", "10  Find your fit", "Settings header")
]
let width = 1440, height = 1540
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
NSColor(calibratedRed: 0.98, green: 0.973, blue: 0.953, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
        .foregroundColor: NSColor(calibratedRed: 0.17, green: 0.27, blue: 0.23, alpha: 1)])
}
text("F2L / An original world for learning", x: 48, y: 35, size: 34, bold: true)
text("10 original assets · Painted paper, warm light, small steps · 11 October 2026", x: 48, y: 86, size: 17)
for (i, item) in items.enumerated() {
    let x = CGFloat(48 + (i % 3) * 456), y = CGFloat(140 + (i / 3) * 342)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 432, height: 322), xRadius: 22, yRadius: 22).fill()
    guard let image = NSImage(contentsOf: assets.appendingPathComponent(item.0)) else { fatalError("Missing \(item.0)") }
    let fit = min(384 / image.size.width, 226 / image.size.height)
    let imageWidth = image.size.width * fit, imageHeight = image.size.height * fit
    image.draw(in: NSRect(x: x + (432 - imageWidth) / 2, y: y + 16 + (226 - imageHeight) / 2, width: imageWidth, height: imageHeight),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    text(item.1, x: x + 24, y: y + 253, size: 19, bold: true)
    text(item.2, x: x + 24, y: y + 284, size: 14)
}
NSGraphicsContext.restoreGraphicsState()
let output = root.appendingPathComponent("docs/previews/f2l-brand-board.png")
try rep.representation(using: .png, properties: [:])!.write(to: output)
print(output.path)
