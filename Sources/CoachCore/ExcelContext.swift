import Foundation

/// What desktop Excel itself reports about the selection, sent with the question so the model doesn't have to
/// read a multi-area selection (Cmd/Ctrl-click) off the screenshot. Mirrors Windows/F2L.Windows/ExcelContext.cs.
public struct ExcelContext: Equatable, Sendable {
    public var sheet: String
    public var areas: [String]
    public var activeCell: String

    /// `selection` and `activeCell` are Excel addresses such as "$A$1:$A$4,$D$1:$D$4" and "$D$1".
    public init?(sheet: String, selection: String, activeCell: String) {
        let areas = selection.replacingOccurrences(of: "$", with: "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !areas.isEmpty else { return nil }
        self.sheet = sheet.trimmingCharacters(in: .whitespacesAndNewlines)
        self.areas = areas
        self.activeCell = activeCell.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
    }

    public var displayLine: String { "Excel has selected \(areas.joined(separator: ", ")) · \(sheet)" }

    /// The line added under the learner's question. It isn't saved in the conversation.
    public var promptLine: String {
        let count = areas.count == 1 ? "1 area" : "\(areas.count) separate areas"
        return "Excel reports (exact, read from Excel, not from the screenshot): sheet \"\(sheet)\"; selected cells \(areas.joined(separator: ", ")) (\(count)); active cell \(activeCell)."
    }
}
