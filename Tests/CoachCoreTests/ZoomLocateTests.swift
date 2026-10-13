import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CoachCore

// Same cases as TestZoomLocate on Windows.
@Suite struct ZoomedLook {
    let window = CGRect(x: 100, y: 50, width: 1400, height: 900)

    @Test func theCropSurroundsTheGuessAndStaysInTheWindow() {
        let small = ZoomLocate.crop(around: CGRect(x: 600, y: 400, width: 30, height: 20), window: window)
        #expect(small.size == ZoomLocate.minimum && small.midX == 615 && small.midY == 410)
        let corner = ZoomLocate.crop(around: CGRect(x: 105, y: 55, width: 20, height: 20), window: window)
        #expect(corner.minX == window.minX && corner.minY == window.minY)
        let big = ZoomLocate.crop(around: CGRect(x: 500, y: 300, width: 200, height: 100), window: window)
        #expect(big.width == 1200 && big.height == 600)
        #expect(ZoomLocate.crop(around: nil, window: window) == window)
    }

    @Test func cropsMapToThePicturesPixels() {
        let crop = CGRect(x: 200, y: 150, width: 420, height: 280)
        #expect(ZoomLocate.pixelRect(crop, window: window, pixels: CGSize(width: 2800, height: 1800)) == CGRect(x: 200, y: 200, width: 840, height: 560))
    }

    @Test func repliesBecomeAPlaceOrNothing() {
        let crop = CGRect(x: 200, y: 150, width: 400, height: 200)
        #expect(ZoomLocate.parse(#"{"found":true,"left":100,"top":200,"right":200,"bottom":400}"#, crop: crop) == CGRect(x: 240, y: 190, width: 40, height: 40))
        #expect(ZoomLocate.parse("```json\n{\"found\":true,\"left\":100,\"top\":200,\"right\":200,\"bottom\":400}\n```", crop: crop) != nil)
        #expect(ZoomLocate.parse(#"{"found":false}"#, crop: crop) == nil)
        #expect(ZoomLocate.parse(#"{"found":true,"left":0,"top":0,"right":1000,"bottom":1000}"#, crop: crop) == nil) // the whole crop
        #expect(ZoomLocate.parse(#"{"found":true,"left":300,"top":200,"right":100,"bottom":400}"#, crop: crop) == nil)
        #expect(ZoomLocate.parse("not json", crop: crop) == nil)
        #expect(ZoomLocate.question(label: "Fill", app: "Microsoft Excel").contains("\"Fill\""))
    }

    @Test func noKeyMeansNoRequest() async {
        let client = CoachClient(apiKey: { "" })
        #expect(await client.zoomLocate(label: "Share", app: "Test", jpeg: Data([1, 2, 3]), crop: window) == nil)
    }
}

/// Draws a toolbar of buttons, crops around a rough guess and asks the selected AI where "Share" is (F2L_LIVE_ZOOM=1).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["F2L_LIVE_ZOOM"] == "1"))
struct LiveZoom {
    @Test func theZoomedLookFindsASmallButton() async throws {
        let client = CoachClient()
        try #require(client.isConfigured, "No selected provider key is configured")
        let size = CGSize(width: 1400, height: 900)
        let labels = ["File", "Edit", "View", "Insert", "Format", "Tools", "Share", "Help"]
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
            NSColor(white: 0.95, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: size.width, height: 60).fill()
            for (index, label) in labels.enumerated() {
                let rect = NSRect(x: 40 + CGFloat(index) * 90, y: 18, width: 72, height: 26)
                NSColor(white: 0.85, alpha: 1).setFill(); NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
                (label as NSString).draw(at: NSPoint(x: rect.minX + 10, y: rect.minY + 5), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
            }
            return true
        }
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let window = CGRect(origin: .zero, size: size)
        let share = CGRect(x: 40 + 6 * 90, y: 18, width: 72, height: 26)
        let guess = share.offsetBy(dx: 120, dy: 30) // a rough first guess, off by a button
        // F2L_LIVE_ZOOM_FULL=1 asks across the whole window instead, to compare.
        let crop = ProcessInfo.processInfo.environment["F2L_LIVE_ZOOM_FULL"] == "1" ? window : ZoomLocate.crop(around: guess, window: window)
        let pixels = ZoomLocate.pixelRect(crop, window: window, pixels: CGSize(width: cg.width, height: cg.height))
        let piece = try #require(cg.cropping(to: pixels))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, piece, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let found = await client.zoomLocate(label: "Share", app: "Test", jpeg: data as Data, crop: crop)
        print("LIVE ZOOM: share at \(share), found \(String(describing: found))")
        let place = try #require(found)
        #expect(share.insetBy(dx: -20, dy: -20).contains(CGPoint(x: place.midX, y: place.midY)))
    }

    /// A busy window with small icon-only buttons, like Excel's ribbon: find the trash can.
    @Test func theZoomedLookFindsASmallIcon() async throws {
        let client = CoachClient()
        try #require(client.isConfigured, "No selected provider key is configured")
        let size = CGSize(width: 1400, height: 900)
        let symbols = ["scissors", "doc.on.doc", "paintbrush", "bold", "italic", "underline", "strikethrough", "textformat.size",
                       "list.bullet", "list.number", "trash", "magnifyingglass", "printer", "square.and.arrow.up", "folder", "paperclip",
                       "link", "photo", "tablecells", "chart.bar", "bell", "gearshape", "arrow.uturn.backward", "arrow.uturn.forward"]
        var trash = CGRect.zero
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
            NSColor(white: 0.96, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: size.width, height: 90).fill()
            for (index, name) in symbols.enumerated() {
                let rect = NSRect(x: 30 + CGFloat(index % 12) * 34, y: 14 + CGFloat(index / 12) * 34, width: 22, height: 22)
                if name == "trash" { trash = rect }
                NSImage(systemSymbolName: name, accessibilityDescription: nil)?.draw(in: rect)
            }
            for row in 0..<20 { ("Quarterly results row \(row + 1)    1,234    5,678    9,012" as NSString)
                .draw(at: NSPoint(x: 40, y: 120 + CGFloat(row) * 34), withAttributes: [.font: NSFont.systemFont(ofSize: 14)]) }
            return true
        }
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let window = CGRect(origin: .zero, size: size)
        let guess = trash.offsetBy(dx: 70, dy: 20) // a rough first guess, two icons off
        let crop = ProcessInfo.processInfo.environment["F2L_LIVE_ZOOM_FULL"] == "1" ? window : ZoomLocate.crop(around: guess, window: window)
        let pixels = ZoomLocate.pixelRect(crop, window: window, pixels: CGSize(width: cg.width, height: cg.height))
        let piece = try #require(cg.cropping(to: pixels))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, piece, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let found = await client.zoomLocate(label: "Delete (trash can icon)", app: "Test", jpeg: data as Data, crop: crop)
        let miss = found.map { hypot($0.midX - trash.midX, $0.midY - trash.midY) } ?? .infinity
        print(String(format: "LIVE ICON (%@): trash at %@, found %@, off by %.0f points", crop == window ? "whole window" : "zoomed",
                     NSStringFromRect(trash), found.map { NSStringFromRect($0) } ?? "nothing", miss))
        #expect(miss < 20)
    }
}
