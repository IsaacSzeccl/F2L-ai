import CoreGraphics
import Testing
@testable import CoachCore

// Excel cells from the gridlines, for a sheet whose column letters can't be read. Mac only.
@Suite struct ExcelGridlines {
    /// A drawn sheet: dark heading bands (40 px on top, 50 on the left), white cells 100 × 30 with grey lines.
    func sheet(width: Int = 900, height: Int = 500, cell: UInt8 = 255, line: UInt8 = 210, heading: UInt8 = 22) -> [UInt8] {
        var pixels = [UInt8](repeating: cell, count: width * height)
        for y in 0..<height { for x in 0..<width {
            if y < 40 || x < 50 { pixels[y * width + x] = heading }
            else if (x - 50) % 100 == 99 || (y - 40) % 30 == 29 { pixels[y * width + x] = line }
        } }
        return pixels
    }

    @Test func cellsComeFromTheLines() throws {
        let grid = try #require(ExcelGrid.read(brightness: sheet(), width: 900, height: 500))
        #expect(grid.top == 40 && grid.left == 50)
        #expect(grid.cell(column: 1, row: 1) == CGRect(x: 50, y: 40, width: 99, height: 29))
        let g7 = try #require(grid.cell(column: 7, row: 7))
        #expect(abs(g7.minX - 649) <= 1 && abs(g7.minY - 219) <= 1)
        #expect(grid.cell(column: 30, row: 1) == nil) // off the picture
    }

    @Test func aScrolledSheetIsPlacedByARowNumberReadOnScreen() throws {
        let grid = try #require(ExcelGrid.read(brightness: sheet(), width: 900, height: 500))
        // "21" read in the second row band: the sheet starts at row 20.
        #expect(grid.firstRow(number: 21, atY: 85) == 20)
        #expect(grid.cell(column: 1, row: 21, firstRow: 20)?.minY == grid.cell(column: 1, row: 2)?.minY)
    }

    @Test func aDarkSheetWorksToo() {
        #expect(ExcelGrid.read(brightness: sheet(cell: 30, line: 80, heading: 60), width: 900, height: 500) != nil)
    }

    @Test func noGridMeansNoCell() {
        #expect(ExcelGrid.read(brightness: [UInt8](repeating: 255, count: 900 * 500), width: 900, height: 500) == nil)
    }
}
