import Foundation

/// Picks Pip's expression from the wording of a question. Mirrors Windows/F2L.Windows/QuestionIntent.cs.
public enum QuestionIntent: Sendable {
    case quickFact, procedural, multiPart, clarificationNeeded

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
    static let ambiguousPattern = regex(#"\b(which one|can you help with this|help me with this|what about that|do you mean|not sure which|this one)\b"#)
    static let multiPattern = regex(#"\b(compare|difference between|explain .+ and|both .+ and|all the steps|why .+ when|what happens if)\b"#)
    static let proceduralPattern = regex(#"\b(how (do|can|to)|where (do|is)|show me|step by step|click|select|open|add these|enter a formula)\b"#)
    static let quickFactPattern = regex(#"\b(hello|hi|hey|what is|what does|define|meaning of|what's a|who is|when did|how many)\b"#)

    public static func classify(_ question: String) -> QuestionIntent {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ r: NSRegularExpression) -> Bool { r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        if matches(ambiguousPattern) { return .clarificationNeeded }
        if matches(multiPattern) || text.filter({ $0 == "?" }).count > 1 { return .multiPart }
        if matches(proceduralPattern) { return .procedural }
        if matches(quickFactPattern) { return .quickFact }
        return .procedural
    }
}
