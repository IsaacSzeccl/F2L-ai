import AppKit
import CoachCore
import Vision

/// Reads the words in a window picture on this Mac (Apple Vision; nothing is sent anywhere), so Pip can find a button,
/// tab or Excel heading exactly where it appears on screen.
enum ScreenReading {
    /// The Mac's preferred languages that Vision can read (yue-Hant-HK → yue-Hant, ja-HK → ja-JP), then English.
    static let recognitionLanguages: [String] = {
        let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
        var chosen: [String] = []
        for preferred in Locale.preferredLanguages {
            let parts = preferred.split(separator: "-").map(String.init)
            guard let language = parts.first else { continue }
            // Script first (zh-Hant, yue-Hant), then the language alone (ja → ja-JP).
            let script = parts.count > 1 && parts[1].count == 4 ? "\(language)-\(parts[1])" : nil
            let match = supported.first { $0 == script } ?? supported.first { $0 == preferred }
                ?? supported.first { $0.split(separator: "-").first.map(String.init) == language }
            if let match, !chosen.contains(match) { chosen.append(match) }
        }
        if !chosen.contains("en-US") { chosen.append("en-US") }
        return chosen
    }()

    /// Lines of words with their places in global top-left points. `frame` is the window the picture shows.
    static func lines(jpeg: Data, frame: CGRect) -> [[ScreenWord]] {
        guard !jpeg.isEmpty, let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // headings like "D" and "12" must stay as they are
        request.minimumTextHeight = 0.006
        // English alone can't read a Chinese or Japanese app: read the Mac's own languages as well.
        request.recognitionLanguages = recognitionLanguages
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { return [] }
        func place(_ box: CGRect) -> CGRect {
            // Vision boxes are normalised with the origin at the bottom left.
            CGRect(x: frame.minX + box.minX * frame.width, y: frame.minY + (1 - box.maxY) * frame.height,
                   width: box.width * frame.width, height: box.height * frame.height)
        }
        return (request.results ?? []).compactMap { observation -> [ScreenWord]? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            var words: [ScreenWord] = []
            text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, range, _, _ in
                guard let word, let box = try? candidate.boundingBox(for: range)?.boundingBox else { return }
                words.append(ScreenWord(text: word, frame: place(box)))
            }
            if words.isEmpty, let box = try? candidate.boundingBox(for: text.startIndex..<text.endIndex)?.boundingBox {
                words = [ScreenWord(text: text, frame: place(box))]
            }
            return words.sorted { $0.frame.minX < $1.frame.minX }
        }
    }
}

/// Render-check self test: draws an Excel-like window (ribbon tabs, column letters, row numbers, some cell text) at
/// Retina scale, reads it back with Vision and checks that D3 and the Insert tab are found where they were drawn.
enum ScreenReadingCheck {
    static func run() -> [String] {
        let size = CGSize(width: 900, height: 560), scale: CGFloat = 2
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return ["could not draw the reading test"] }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1) // draw top-down like the screen
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSColor.white.setFill(); CGRect(origin: .zero, size: size).fill()
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 12) {
            NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black]).draw(at: CGPoint(x: x, y: y))
        }
        for (i, tab) in ["Home", "Insert", "Draw", "Page Layout", "Formulas", "Data"].enumerated() { text(tab, 20 + CGFloat(i) * 90, 14, size: 13) }
        let gridX: CGFloat = 60, gridY: CGFloat = 120, colW: CGFloat = 72, rowH: CGFloat = 22
        NSColor(white: 0.93, alpha: 1).setFill()
        CGRect(x: gridX, y: gridY - 22, width: size.width - gridX, height: 22).fill()
        CGRect(x: 20, y: gridY, width: gridX - 20, height: size.height - gridY).fill()
        for (i, letter) in ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"].enumerated() {
            text(letter, gridX + CGFloat(i) * colW + colW / 2 - 4, gridY - 19)
        }
        for row in 1...19 { text("\(row)", 28, gridY + CGFloat(row - 1) * rowH + 4) }
        text("Budget", gridX + 6, gridY + 4); text("120", gridX + colW + 6, gridY + rowH + 4)
        NSGraphicsContext.current = nil
        guard let image = context.makeImage(), let jpeg = ScreenCaptureService.jpegData(image) else { return ["could not encode the reading test"] }
        let words = ScreenReading.lines(jpeg: jpeg, frame: CGRect(origin: .zero, size: size))
        var failures: [String] = []
        let expected = CGRect(x: gridX + 3 * colW, y: gridY + 2 * rowH, width: colW, height: rowH)
        if let d3 = ScreenText.excelCell("D3", words: words.flatMap { $0 }) {
            if abs(d3.midX - expected.midX) > 8 || abs(d3.midY - expected.midY) > 6 { failures.append("D3 found at \(d3), drawn at \(expected)") }
        } else {
            failures.append("D3 not found from the headings read on screen (\(words.flatMap { $0 }.map(\.text).prefix(40)))")
        }
        let insert = TargetSnap.snap(box: CGRect(x: 600, y: 300, width: 40, height: 20), label: "Insert", candidates: ScreenText.candidates(lines: words))
        if insert == nil || abs(insert!.midX - (110 + 20)) > 25 || abs(insert!.midY - 22) > 8 { failures.append("Insert tab not found where drawn: \(String(describing: insert))") }
        return failures
    }
}
