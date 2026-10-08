import Foundation

/// Reply style shared with the Windows companion (Windows/F2L.Windows/TeachingReply.cs). Keep both in step.
public enum TeachingReply {
    public static let style = """
        Teach directly. Start with the answer or the next action: "Select A1", "Open Insert", or "SUM adds numbers".
        Default to one actionable step and its essential reason, in 1–3 short sentences, usually under 55 words; a multi-step task lists all its steps.
        Give more detail only when requested or needed to make the step usable. Preserve exact formulas and warnings.
        No greeting, praise, reassurance, preamble, recap, self-description, or invitation to ask more.
        Never add "Great question", "Happy to help", "Let's dive in", "Don't worry", or "Let me know".
        Do not narrate what you are about to explain. Explain it. Ask a question only if a missing fact prevents a correct step.
        Never claim the learner completed an action without evidence. Use the learner's language.
        """

    // Remove only stock standalone openings/closings; never cut a real instruction, formula, or warning.
    static let opening = try! NSRegularExpression(
        pattern: #"\A\s*(?:(?:sure(?: thing)?|certainly|absolutely|great question|good question|happy to help|I'd be happy to help|let's dive in)[!.:]\s*)+"#,
        options: [.caseInsensitive])
    static let closing = try! NSRegularExpression(
        pattern: #"\s+(?:Let me know if you (?:have any questions|need (?:any |more |further )?help|need anything else)|Feel free to ask (?:any questions|if you need (?:more )?help))[!.]?\s*\z"#,
        options: [.caseInsensitive])

    public static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var clean = opening.stringByReplacingMatches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed), withTemplate: "")
        clean = closing.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? trimmed : clean
    }
}
