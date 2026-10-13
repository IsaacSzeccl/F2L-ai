import AppKit
import CoachCore

struct ExcelSelectionResult: Sendable {
    let context: ExcelContext?
    let message: String
}

/// Only called for the learner's active desktop Excel session while screen sharing is enabled.
/// The script reads every selection area without selecting cells or activating Excel.
final class ExcelSelectionReader {
    private let queue = DispatchQueue(label: "ai.f2l.excel-selection", qos: .userInitiated)
    private static let script = """
        with timeout of 5 seconds
            tell application "Microsoft Excel"
                if (count of workbooks) is 0 then return {}
                set sheetName to name of active sheet
                set selectedAddresses to {}
                repeat with selectedArea in (get areas of selection)
                    set end of selectedAddresses to get address selectedArea reference style A1
                end repeat
                set activeAddress to get address active cell reference style A1
                return {sheetName, selectedAddresses, activeAddress}
            end tell
        end timeout
        """

    static func validateScript() -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: Self.script), script.compileAndReturnError(&error) else {
            return error?[NSAppleScript.errorMessage] as? String ?? "Excel selection script did not compile"
        }
        return nil
    }

    /// Whether F2L may send Excel Apple events. With `ask: false` macOS never shows its "control Microsoft Excel"
    /// prompt: only a question the learner just sent may ask, never the background selection checks. Without this,
    /// every poll while the prompt was unanswered (or after a stale grant) asked again.
    nonisolated static func mayControlExcel(ask: Bool) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.microsoft.Excel")
        guard let desc = target.aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask) == noErr
    }

    static let notAllowed = "Selection unavailable · allow F2L → Microsoft Excel in System Settings → Privacy & Security → Automation."

    func read(ask: Bool = false) async -> ExcelSelectionResult {
        await withCheckedContinuation { continuation in
            queue.async {
                guard Self.mayControlExcel(ask: ask) else {
                    continuation.resume(returning: ExcelSelectionResult(context: nil, message: Self.notAllowed))
                    return
                }
                var error: NSDictionary?
                let result = NSAppleScript(source: Self.script)?.executeAndReturnError(&error)
                if let error {
                    let denied = (error[NSAppleScript.errorNumber] as? Int) == -1743
                    continuation.resume(returning: ExcelSelectionResult(context: nil, message: denied
                        ? "Selection unavailable · allow F2L → Excel in System Settings → Privacy & Security → Automation."
                        : "Selection unavailable · finish editing the cell or close Excel’s dialog."))
                    return
                }
                guard let result, result.numberOfItems == 3,
                      let sheet = result.atIndex(1)?.stringValue, let list = result.atIndex(2),
                      let active = result.atIndex(3)?.stringValue, list.numberOfItems > 0 else {
                    continuation.resume(returning: ExcelSelectionResult(context: nil, message: "Selection unavailable · open a worksheet in Excel."))
                    return
                }
                let addresses = (1...list.numberOfItems).compactMap { list.atIndex($0)?.stringValue }
                let context = ExcelContext(sheet: sheet, selection: addresses.joined(separator: ","), activeCell: active)
                continuation.resume(returning: ExcelSelectionResult(context: context, message: context?.displayLine ?? "Selection unavailable"))
            }
        }
    }

    /// Excel's own numbers for where `address` sits on the sheet (see ExcelCellMetrics). Nil with frozen or split
    /// panes, which this placement doesn't handle, or when Excel can't answer. Never selects or scrolls.
    func cellMetrics(_ address: String) async -> ExcelCellMetrics? {
        let clean = address.uppercased().filter { $0.isLetter || $0.isNumber || $0 == ":" }
        guard !clean.isEmpty, clean.count <= 24 else { return nil }
        let source = """
            with timeout of 5 seconds
                tell application "Microsoft Excel"
                    if (count of workbooks) is 0 then return {}
                    set w to active window
                    if (freeze panes of w) or (split of w) then return {}
                    set vr to visible range of w
                    set r to range "\(clean)" of active sheet
                    return {(left position of vr) as real, (top of vr) as real, (left position of r) as real, (top of r) as real, ¬
                        (width of r) as real, (height of r) as real, (zoom of w) as real, display headings of w}
                end tell
            end timeout
            """
        return await withCheckedContinuation { continuation in
            queue.async {
                guard Self.mayControlExcel(ask: false) else { continuation.resume(returning: nil); return }
                var error: NSDictionary?
                guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil, result.numberOfItems == 8 else {
                    continuation.resume(returning: nil); return
                }
                let numbers = (1...7).compactMap { result.atIndex($0)?.doubleValue }
                guard numbers.count == 7 else { continuation.resume(returning: nil); return }
                continuation.resume(returning: ExcelCellMetrics(visibleLeft: numbers[0], visibleTop: numbers[1], left: numbers[2], top: numbers[3],
                                                                width: numbers[4], height: numbers[5], zoom: numbers[6],
                                                                headings: result.atIndex(8)?.booleanValue ?? true))
            }
        }
    }
}
