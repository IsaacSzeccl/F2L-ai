import AppKit
import CoachCore

/// Finds an Excel cell on screen from the worksheet's gridlines in a picture of the window (see ExcelGrid), when its
/// column letters can't be read. The worksheet area comes from Accessibility (AXLayoutArea); the first visible row
/// from a row number read on screen, and the first visible column from a column letter when one was read, else A.
enum ExcelGridReader {
    static func place(_ address: String, jpeg: Data, window: CGRect, grid area: CGRect, words: [ScreenWord]) -> CGRect? {
        let parts = address.uppercased().replacingOccurrences(of: "$", with: "").split(separator: ":").map(String.init)
        guard (1...2).contains(parts.count), let first = CellReference.parse(parts[0]),
              let last = parts.count == 2 ? CellReference.parse(parts[1]) : first,
              let source = CGImageSourceCreateWithData(jpeg as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              window.width > 0, window.height > 0 else { return nil }
        let sx = CGFloat(image.width) / window.width, sy = CGFloat(image.height) / window.height
        let crop = CGRect(x: (area.minX - window.minX) * sx, y: (area.minY - window.minY) * sy, width: area.width * sx, height: area.height * sy)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard crop.width >= 120, crop.height >= 80, let piece = image.cropping(to: crop) else { return nil }
        let width = piece.width, height = piece.height
        var brightness = [UInt8](repeating: 0, count: width * height)
        let drawn = brightness.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(piece, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let grid = ExcelGrid.read(brightness: brightness, width: width, height: height) else { return nil }
        // Screen points of a pixel in the piece, and back.
        func screen(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: area.minX + x / sx, y: area.minY + y / sy) }
        let headings = CGRect(origin: area.origin, size: CGSize(width: CGFloat(grid.left) / sx, height: area.height))
        let columnBand = CGRect(origin: area.origin, size: CGSize(width: area.width, height: CGFloat(grid.top) / sy))
        // A row number read in the row headings says which row its band is (the sheet may be scrolled down).
        var firstRow = 1
        if let number = words.first(where: { Int($0.text) != nil && headings.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }),
           let value = Int(number.text), let row = grid.firstRow(number: value, atY: Int((number.frame.midY - area.minY) * sy)) {
            firstRow = row
        }
        // A column letter read in the headings does the same for columns; Apple's reader rarely sees them, so A is assumed.
        var firstColumn = 1
        let edges = [grid.left] + grid.columns
        if let letter = words.first(where: { word in
            columnBand.contains(CGPoint(x: word.frame.midX, y: word.frame.midY)) && word.text.count <= 3
                && word.text.allSatisfy({ $0.isUppercase && $0.isLetter })
        }), let column = CellReference.parse("\(letter.text)1")?.column {
            let x = Int((letter.frame.midX - area.minX) * sx)
            if let band = edges.indices.dropLast().first(where: { edges[$0] <= x && x < edges[$0 + 1] }) { firstColumn = column - band }
        }
        guard let start = grid.cell(column: min(first.column, last.column), row: min(first.row, last.row), firstColumn: firstColumn, firstRow: firstRow),
              let end = grid.cell(column: max(first.column, last.column), row: max(first.row, last.row), firstColumn: firstColumn, firstRow: firstRow)
        else { return nil }
        let pixels = start.union(end)
        let origin = screen(pixels.minX, pixels.minY)
        return CGRect(x: origin.x, y: origin.y, width: pixels.width / sx, height: pixels.height / sy)
    }
}
