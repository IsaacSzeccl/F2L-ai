import Foundation

/// Reply style shared with the Windows companion (Windows/F2L.Windows/TeachingReply.cs). Keep both in step.
public enum TeachingReply {
    public static let style = """
        Teach like a patient colleague sitting beside the learner: warm, plain and specific, never patronizing.
        Start with the answer or the next action: "Open notion.so and sign in", "Click New page", or "SUM adds numbers".
        A simple question gets 1–3 short sentences. A task with more than one action lists all its steps, and every step is
        one action in one or two short sentences: what to do, where it is on screen (for example "top right, the blue Share
        button"), and, when it helps the learner check, what they should see next. One click per step where possible.
        Give more detail only when requested or needed to make the step usable. Preserve exact formulas and warnings.
        No stock openings or closings: never add "Great question", "Happy to help", "Let's dive in", "Don't worry", or "Let me know".
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
