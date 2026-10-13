import CoreGraphics
import Foundation

/// A word read from the screenshot on this computer (Apple Vision on Mac, Windows OCR on Windows), with where it is
/// on screen in global top-left coordinates. Mirrors Windows/F2L.Windows/ScreenText.cs.
public struct ScreenWord: Equatable, Sendable {
    public var text: String
    public var frame: CGRect
    public init(text: String, frame: CGRect) {
        self.text = text
        self.frame = frame
    }
}

public enum ScreenText {
    /// Every run of one to four neighbouring words on a line, as a control candidate: "Recommended Charts" is two words
    /// that together name one button.
    public static func candidates(lines: [[ScreenWord]]) -> [ControlCandidate] {
        var result: [ControlCandidate] = []
        for line in lines {
            for start in line.indices {
                var frame = CGRect.null
                var words: [String] = []
                for end in start..<min(line.count, start + 4) {
                    // A big gap means the next word belongs to another control.
                    if end > start, line[end].frame.minX - line[end - 1].frame.maxX > max(14, line[end].frame.height * 1.2) { break }
                    frame = frame.union(line[end].frame)
                    words.append(line[end].text)
                    result.append(ControlCandidate(frame: frame, name: words.joined(separator: " ")))
                }
            }
        }
        return result
    }

    /// Where `address` (a cell or range such as "D1:D4") is on screen, found from Excel's column letters and row numbers
    /// read off the screenshot. Nil when the needed headings aren't visible.
    public static func excelCell(_ address: String, words: [ScreenWord]) -> CGRect? {
        let parts = address.uppercased().replacingOccurrences(of: "$", with: "").split(separator: ":").map(String.init)
        guard (1...2).contains(parts.count), let first = CellReference.parse(parts[0]),
              let last = parts.count == 2 ? CellReference.parse(parts[1]) : first,
              let columns = columnHeadings(words), let rows = rowHeadings(words) else { return nil }
        guard let left = span(of: min(first.column, last.column), in: columns), let right = span(of: max(first.column, last.column), in: columns),
              let top = span(of: min(first.row, last.row), in: rows), let bottom = span(of: max(first.row, last.row), in: rows) else { return nil }
        return CGRect(x: left.lowerBound, y: top.lowerBound, width: right.upperBound - left.lowerBound, height: bottom.upperBound - top.lowerBound)
    }

    /// Column letters along one horizontal band, as (column number, centre x), left to right. Reading single letters
    /// is unreliable (some are missed, "C" may come back as "c"), so the band whose letters best fit evenly spaced
    /// columns wins.
    static func columnHeadings(_ words: [ScreenWord]) -> [(index: Int, center: CGFloat)]? {
        let letters = words.compactMap { word -> (Int, ScreenWord)? in
            let text = word.text.trimmingCharacters(in: .whitespaces).uppercased()
            guard (1...3).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isLetter }),
                  let cell = CellReference.parse(text + "1") else { return nil }
            return (cell.column, word)
        }
        return headings(letters, band: { $0.frame.midY }, position: { $0.frame.midX })
    }

    /// Row numbers down one vertical band, as (row number, centre y), top to bottom.
    static func rowHeadings(_ words: [ScreenWord]) -> [(index: Int, center: CGFloat)]? {
        let numbers = words.compactMap { word -> (Int, ScreenWord)? in
            guard let row = Int(word.text.trimmingCharacters(in: .whitespaces)), row >= 1, row <= 1_048_576 else { return nil }
            return (row, word)
        }
        return headings(numbers, band: { $0.frame.midX }, position: { $0.frame.midY })
    }

    /// Groups items lying on the same band (within 6 points). In each band, finds evenly spaced headings: the spacing
    /// most pairs agree on, and the items that sit on that line (missing ones are fine). The band with the most such
    /// items wins; at least three, so stray letters or numbers in cells don't count.
    static func headings(_ items: [(Int, ScreenWord)], band: (ScreenWord) -> CGFloat, position: (ScreenWord) -> CGFloat)
        -> [(index: Int, center: CGFloat)]? {
        var groups: [[(index: Int, center: CGFloat)]] = []
        var bands: [CGFloat] = []
        for item in items.sorted(by: { band($0.1) < band($1.1) }) {
            if let last = bands.last, abs(last - band(item.1)) <= 6 { groups[groups.count - 1].append((item.0, position(item.1))) }
            else { groups.append([(item.0, position(item.1))]); bands.append(band(item.1)) }
        }
        var best: [(index: Int, center: CGFloat)] = []
        for group in groups where group.count >= 3 {
            var steps: [CGFloat] = []
            for a in group { for b in group where b.index > a.index { steps.append((b.center - a.center) / CGFloat(b.index - a.index)) } }
            for step in steps where step > 4 {
                // The line through the items with this spacing, anchored where most of them agree.
                let offsets = group.map { $0.center - CGFloat($0.index) * step }.sorted()
                let offset = offsets[offsets.count / 2]
                let fits = group.filter { abs($0.center - (offset + CGFloat($0.index) * step)) <= step * 0.3 }
                var seen = Set<Int>()
                let unique = fits.sorted { $0.index < $1.index }.filter { seen.insert($0.index).inserted }
                if unique.count > best.count { best = unique }
            }
        }
        return best.count >= 3 ? best : nil
    }

    /// The extent of heading `index`: halfway to its neighbours' centres. Columns or rows just past the visible
    /// headings are extended by the average spacing.
    static func span(of index: Int, in headings: [(index: Int, center: CGFloat)]) -> ClosedRange<CGFloat>? {
        guard let first = headings.first, let last = headings.last, headings.count >= 2 else { return nil }
        let step = (last.center - first.center) / CGFloat(last.index - first.index)
        guard step > 0, index >= first.index - 1, index <= last.index + 1 else { return nil }
        func center(_ i: Int) -> CGFloat {
            headings.first { $0.index == i }?.center ?? first.center + CGFloat(i - first.index) * step
        }
        let c = center(index)
        let low = (c + center(index - 1)) / 2, high = (c + center(index + 1)) / 2
        return min(low, high)...max(low, high)
    }
}
