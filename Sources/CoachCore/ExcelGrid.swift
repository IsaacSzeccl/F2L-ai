import CoreGraphics
import Foundation

/// Excel's cells found from the grid's own lines in a picture of the worksheet area. Apple's text reader misses
/// Excel's single-letter column headings (A, B, C…), so cells can't always be found by reading them; the gridlines and
/// the heading bands are always drawn. Works on brightness only, so the light and dark looks both work.
public struct ExcelGrid: Equatable, Sendable {
    /// Where the cells start, past the column headings (top) and row numbers (left), in pixels of the picture.
    public var top: Int
    public var left: Int
    /// The x of each vertical gridline right of `left`, and the y of each horizontal one below `top`, in order.
    public var columns: [Int]
    public var rows: [Int]

    /// Reads the grid from brightness values (0 dark … 255 light), `width` × `height`, row by row. Nil when no grid
    /// with headings is clear enough.
    public static func read(brightness: [UInt8], width: Int, height: Int) -> ExcelGrid? {
        guard width >= 120, height >= 80, brightness.count == width * height else { return nil }
        func at(_ x: Int, _ y: Int) -> Int { Int(brightness[y * width + x]) }
        // The empty cells' colour: the most common brightness in the middle of the sheet.
        var counts = [Int](repeating: 0, count: 256)
        for y in stride(from: height / 3, to: height * 2 / 3, by: 2) { for x in stride(from: width / 3, to: width * 2 / 3, by: 2) { counts[at(x, y)] += 1 } }
        guard let cell = counts.indices.max(by: { counts[$0] < counts[$1] }) else { return nil }
        func isCell(_ value: Int) -> Bool { abs(value - cell) <= 6 }
        // The heading bands differ from the cells: walk in from the top and from the left until cells begin.
        func bandEnd(along length: Int, sample: (Int) -> [Int]) -> Int? {
            var run = 0
            for position in 0..<min(length, 120) {
                let values = sample(position)
                if values.filter(isCell).count * 3 >= values.count * 2 { run += 1 } else { run = 0 }
                if run == 4 { return position - 3 }
            }
            return nil
        }
        let xs = stride(from: width / 4, to: width * 3 / 4, by: max(1, width / 40)).map { $0 }
        let ys = stride(from: height / 4, to: height * 3 / 4, by: max(1, height / 40)).map { $0 }
        guard let top = bandEnd(along: height, sample: { y in xs.map { at($0, y) } }), top >= 8,
              let left = bandEnd(along: width, sample: { x in ys.map { at(x, $0) } }), left >= 8 else { return nil }
        // A gridline is darker than the cells (lighter in a dark sheet) at the same place near both ends of the sheet,
        // so text in a cell is not taken for a line.
        func lines(count: Int, from start: Int, near a: Int, and b: Int, value: (Int, Int) -> Int) -> [Int] {
            var found: [Int] = []
            var position = start + 2
            while position < count {
                func off(_ across: Int) -> Bool { abs(value(position, across) - cell) >= 12 }
                if off(a) && off(b) {
                    var end = position
                    while end + 1 < count, abs(value(end + 1, a) - cell) >= 12 { end += 1 }
                    found.append((position + end) / 2)
                    position = end + 1
                } else {
                    position += 1
                }
            }
            // Lines closer than 6 pixels are one line drawn thick.
            return found.reduce(into: [Int]()) { kept, line in if let last = kept.last, line - last < 6 { return }; kept.append(line) }
        }
        let columns = lines(count: width, from: left, near: min(height - 1, top + 3), and: height - 4) { x, y in at(x, y) }
        let rows = lines(count: height, from: top, near: min(width - 1, left + 3), and: width - 4) { y, x in at(x, y) }
        guard columns.count >= 2, rows.count >= 2 else { return nil }
        return ExcelGrid(top: top, left: left, columns: columns, rows: rows)
    }

    /// The cell `column`, `row` (1 = A, 1), given the first visible column and row, in the picture's pixels.
    public func cell(column: Int, row: Int, firstColumn: Int = 1, firstRow: Int = 1) -> CGRect? {
        let c = column - firstColumn, r = row - firstRow
        let xEdges = [left] + columns, yEdges = [top] + rows
        guard c >= 0, r >= 0, c + 1 < xEdges.count, r + 1 < yEdges.count else { return nil }
        return CGRect(x: xEdges[c], y: yEdges[r], width: xEdges[c + 1] - xEdges[c], height: yEdges[r + 1] - yEdges[r])
    }

    /// The first visible row, from a row number read in the row headings: the band it sits in says which row that is.
    public func firstRow(number: Int, atY y: Int) -> Int? {
        let edges = [top] + rows
        guard let band = edges.indices.dropLast().first(where: { edges[$0] <= y && y < edges[$0 + 1] }) else { return nil }
        return number - band
    }
}
