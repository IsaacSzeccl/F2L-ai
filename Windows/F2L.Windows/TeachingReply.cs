using System.Text.RegularExpressions;

namespace F2L.Windows;

internal static partial class TeachingReply
{
    internal const string Style = """
        Teach directly. Start with the answer or the next action: "Select A1", "Open Insert", or "SUM adds numbers".
        Default to one actionable step and its essential reason, in 1–3 short sentences, usually under 55 words; a multi-step task lists all its steps.
        Give more detail only when requested or needed to make the step usable. Preserve exact formulas and warnings.
        No greeting, praise, reassurance, preamble, recap, self-description, or invitation to ask more.
        Never add "Great question", "Happy to help", "Let's dive in", "Don't worry", or "Let me know".
        Do not narrate what you are about to explain. Explain it. Ask a question only if a missing fact prevents a correct step.
        Never claim the learner completed an action without evidence. Use the learner's language.
        """;

    // Remove only stock standalone openings/closings; never cut a real instruction, formula, or warning.
    [GeneratedRegex(@"\A\s*(?:(?:sure(?: thing)?|certainly|absolutely|great question|good question|happy to help|I'd be happy to help|let's dive in)[!.:]\s*)+", RegexOptions.IgnoreCase)]
    private static partial Regex Opening();
    [GeneratedRegex(@"\s+(?:Let me know if you (?:have any questions|need (?:any |more |further )?help|need anything else)|Feel free to ask (?:any questions|if you need (?:more )?help))[!.]?\s*\z", RegexOptions.IgnoreCase)]
    private static partial Regex Closing();

    internal static string Clean(string text)
    {
        var clean = Opening().Replace(text.Trim(), "");
        clean = Closing().Replace(clean, "").Trim();
        return clean.Length == 0 ? text.Trim() : clean;
    }
}
