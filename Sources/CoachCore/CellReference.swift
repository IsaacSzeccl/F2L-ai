import Foundation

/// A single spreadsheet cell such as A1. Mirrors Windows/F2L.Windows/CellReference.cs.
public struct CellReference: Equatable, Sendable {
    public let address: String
    public let row: Int
    public let column: Int

    // ASCII-only edges, so a reference written straight after Chinese text ("圈出A1") is still found.
    static let pattern = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_!])\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})(?![A-Za-z0-9_])"#)
    static let pointingVerb = try! NSRegularExpression(
        pattern: #"\b(circle|highlight|mark|locate|find|point|show)\b|圈|標記|标记"#, options: [.caseInsensitive])
    static let fillerWords = try! NSRegularExpression(
        pattern: #"\b(please|can|could|would|you|circle|highlight|mark|locate|find|point|show|me|at|to|the|cell|in|on|excel|for)\b|圈出|圈|標記|标记|請|请"#,
        options: [.caseInsensitive])

    public static func parse(_ text: String) -> CellReference? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: range), match.range == range,
              let lettersRange = Range(match.range(at: 1), in: trimmed),
              let rowRange = Range(match.range(at: 2), in: trimmed) else { return nil }
        let letters = trimmed[lettersRange].uppercased()
        let column = letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
        guard let row = Int(trimmed[rowRange]), row <= 1_048_576, column <= 16_384 else { return nil }
        return CellReference(address: "\(letters)\(row)", row: row, column: column)
    }

    public static func find(_ question: String) -> [CellReference] {
        var seen = Set<String>()
        return pattern.matches(in: question, range: NSRange(question.startIndex..., in: question)).compactMap { match in
            guard let r = Range(match.range, in: question), let cell = parse(String(question[r])),
                  seen.insert(cell.address).inserted else { return nil }
            return cell
        }
    }

    public static func matchesRequest(_ proposed: CellReference, _ requested: [CellReference]) -> Bool {
        requested.isEmpty || (requested.count == 1 && requested[0].address == proposed.address)
    }

    public static func isPointingOnly(_ question: String) -> Bool {
        let full = NSRange(question.startIndex..., in: question)
        guard find(question).count == 1, pointingVerb.firstMatch(in: question, range: full) != nil else { return false }
        var rest = pattern.stringByReplacingMatches(in: question, range: full, withTemplate: " ")
        rest = fillerWords.stringByReplacingMatches(in: rest, range: NSRange(rest.startIndex..., in: rest), withTemplate: " ")
        return rest.allSatisfy { $0.isWhitespace || ".,?!".contains($0) }
    }

    public var columnLetters: String { String(address.prefix { $0.isLetter }) }
}
