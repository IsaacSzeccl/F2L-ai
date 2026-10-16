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

    /// The language the learner wrote in, by its letters: Pip answers in it even when the app on screen uses another
    /// language (an English question about a Chinese Gemini gets English steps). Nil when it can't tell.
    public static func language(of question: String) -> String? {
        var latin = 0, han = 0, kana = 0, hangul = 0
        for scalar in question.unicodeScalars {
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            case 0x3040...0x30FF: kana += 1
            case 0xAC00...0xD7AF: hangul += 1
            case 0x3400...0x9FFF, 0xF900...0xFAFF: han += 1
            default: break
            }
        }
        if kana > 0 { return "Japanese" }
        if hangul > 0 { return "Korean" }
        if han > 0 { return han * 2 >= latin ? "Chinese" : "English" }
        return latin >= 3 ? "English" : nil
    }

    /// The line added to a question that says which language to answer in.
    public static func languageLine(_ question: String) -> String {
        guard let language = language(of: question) else { return "" }
        return " The learner wrote in \(language): answer in \(language), naming on-screen controls in \(language) with their on-screen names in brackets."
    }

    public static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var clean = opening.stringByReplacingMatches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed), withTemplate: "")
        clean = closing.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? trimmed : clean
    }
}
