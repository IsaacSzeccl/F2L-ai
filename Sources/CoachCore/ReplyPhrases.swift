import Foundation

/// Phrases remain available until the learner advances. Never split a formula at punctuation.
public enum ReplyPhrases {
    public static func pages(reply: String, steps: [String]) -> [String] {
        let intro = TeachingReply.clean(reply)
        if !steps.isEmpty { return [intro] + steps.enumerated().map { "\($0.offset + 1). \($0.element)" } }
        return intro.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// UTF-16 ranges match AppKit's attributed strings; whitespace and formulas stay intact.
    public static func words(in text: String) -> [NSRange] {
        let pattern = try! NSRegularExpression(pattern: #"\S+\s*"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
    }
}
