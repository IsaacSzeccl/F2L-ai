// Render the production atlas into four looping GIF previews using the app's canvas and timings.
// Run from the repository root: swift scripts/tools/preview_pip.swift
import Foundation
import CoreGraphics
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pip = root.appendingPathComponent("Windows/F2L.Windows/Assets/Pip")
let output = root.appendingPathComponent("build/pip-previews")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: pip.appendingPathComponent("frames.json"))) as! [String: Any]
let sheet = manifest["playful"] as! [String: Any]
let frames = sheet["frames"] as! [[Int]]
let source = CGImageSourceCreateWithURL(pip.appendingPathComponent("playful.png") as CFURL, nil)!
let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let scale = 288.0 / (Double(atlas.width) / 4)
for (row, name) in ["wink", "dance", "stretch", "peekaboo"].enumerated() {
    let url = output.appendingPathComponent("pip-\(name).gif")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, 4, nil)!
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for column in 0..<4 {
        let rect = frames[row * 4 + column]
        let sprite = atlas.cropping(to: CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]))!
        let context = CGContext(data: nil, width: 320, height: 340, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.976, blue: 0.937, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 340))
        let width = Double(rect[2]) * scale, height = Double(rect[3]) * scale
        context.interpolationQuality = .high
        context.draw(sprite, in: CGRect(x: (320 - width) / 2, y: 15, width: width, height: height))
        // Hold the last frame longer in previews so the loop has a little breathing room.
        let delay = [0.35, 0.65, 0.65, 1.55][column]
        CGImageDestinationAddImage(destination, context.makeImage()!,
                                  [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not export \(name)") }
    print(url.path)
}
