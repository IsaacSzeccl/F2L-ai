import Foundation

/// Whether the learner's real Excel selection already does what a step asks. Only steps about selecting or clicking
/// cells can be checked; typing, menus and formulas are left to the learner's "Done".
public enum StepCheck {
    public enum Result: Equatable, Sendable {
        case notCheckable
        case done
        /// The cells or ranges from the step that the selection doesn't cover yet.
        case missing([String])
    }

    static let action = try! NSRegularExpression(pattern: #"\b(select|click|drag|highlight|choose|hold|extend)\b"#, options: [.caseInsensitive])
    static let adding = try! NSRegularExpression(pattern: #"\b(command|cmd|ctrl|control)\b|⌘"#, options: [.caseInsensitive])
    static let formula = try! NSRegularExpression(pattern: #"=\S+"#)
    /// A1, A1:A4, A1-A4 and "A1 to A4" (also "from A1 to A4").
    static let reference = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_!])\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})(?:\s*(?::|-|–|\bto\b|\bthrough\b)\s*\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6}))?(?![A-Za-z0-9_])"#,
        options: [.caseInsensitive])

    struct Area: Equatable {
        var top: Int, left: Int, bottom: Int, right: Int
        func covers(_ other: Area) -> Bool { left <= other.left && right >= other.right && top <= other.top && bottom >= other.bottom }
    }

    static func area(_ address: String) -> Area? {
        let parts = address.split(separator: ":").map(String.init)
        guard (1...2).contains(parts.count), let a = CellReference.parse(parts[0]) else { return nil }
        let b = parts.count == 2 ? CellReference.parse(parts[1]) : a
        guard let b else { return nil }
        return Area(top: min(a.row, b.row), left: min(a.column, b.column), bottom: max(a.row, b.row), right: max(a.column, b.column))
    }

    /// The cells and ranges a step names, in order, as "A1" or "A1:A4". Formulas are ignored.
    public static func references(in step: String) -> [String] {
        let text = formula.stringByReplacingMatches(in: step, range: NSRange(step.startIndex..., in: step), withTemplate: " ")
        var seen = Set<String>()
        return reference.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            func part(_ i: Int) -> String? { Range(match.range(at: i), in: text).map { String(text[$0]).uppercased() } }
            guard let column = part(1), let row = part(2) else { return nil }
            var address = column + row
            if let endColumn = part(3), let endRow = part(4) { address += ":" + endColumn + endRow }
            guard area(address) != nil, seen.insert(address).inserted else { return nil }
            return address
        }
    }

    /// `earlier` are the steps before this one: when this step adds to the selection with Command or Ctrl,
    /// the cells they selected must still be selected too.
    public static func check(step: String, earlier: [String] = [], selected areas: [String]) -> Result {
        var wanted = references(in: step)
        guard !wanted.isEmpty, action.firstMatch(in: step, range: NSRange(step.startIndex..., in: step)) != nil else { return .notCheckable }
        if adding.firstMatch(in: step, range: NSRange(step.startIndex..., in: step)) != nil {
            let kept = earlier.filter { action.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }.flatMap(references)
            wanted = kept.filter { !wanted.contains($0) } + wanted
        }
        let selected = areas.compactMap(area)
        let missing = wanted.filter { address in
            guard let needed = area(address) else { return false }
            return !selected.contains { $0.covers(needed) }
        }
        return missing.isEmpty ? .done : .missing(missing)
    }
}
