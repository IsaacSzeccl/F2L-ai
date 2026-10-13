import AppKit
import CoachCore

/// Mirrors ExcelTargetResult in Windows/F2L.Windows/ExcelTargetResolver.cs.
struct ExcelTargetResult {
    var bounds: CGRect?
    var message: String
    var sheet: String?
    var verified: Bool { bounds.map(CompanionPlacement.isUsable) ?? false }
}

/// Finds where a cell is in desktop Excel. Reads geometry only: never selects, edits, scrolls, activates or saves.
/// Wording follows ExcelTargetResolver.cs.
@MainActor
final class ExcelTargetResolver {
    private var busy = false

    func resolve(_ capture: CapturedScreen, _ cell: CellReference) async -> ExcelTargetResult {
        guard capture.app.isExcel else {
            return ExcelTargetResult(message: "I can verify \(cell.address) in desktop Excel. For Excel in a browser, I won't guess a cell's position.")
        }
        guard !busy else { return ExcelTargetResult(message: "Excel is still responding. Try again after closing any open Excel dialog.") }
        busy = true
        defer { busy = false }
        guard ScreenCaptureService.isCurrent(capture) else { return ExcelTargetResult(message: "The app window changed. Ask again with Excel visible.") }
        // Excel for Mac doesn't report cell positions to Accessibility, so there is nothing to verify against yet.
        return ExcelTargetResult(message: "Select \(cell.address): column \(cell.columnLetters), row \(cell.row). On Mac I can't verify where that cell is on screen yet, so I won't draw a guessed outline.")
    }
}
