using System.Text.RegularExpressions;

namespace F2L.Windows;

internal static partial class TeachingReply
{
    internal const string Style = """
        Teach like a patient colleague sitting beside the learner: warm, plain and specific, never patronizing.
        Start with the answer or the next action: "Open notion.so and sign in", "Click New page", or "SUM adds numbers".
        A simple question gets 1–3 short sentences. A task with more than one action lists all its steps, and every step is
        one action in one or two short sentences: what to do, where it is on screen (for example "top right, the blue Share
        button"), and, when it helps the learner check, what they should see next. One click per step where possible.
        Give more detail only when requested or needed to make the step usable. Preserve exact formulas and warnings.
        No stock openings or closings: never add "Great question", "Happy to help", "Let's dive in", "Don't worry", or "Let me know".
        Do not narrate what you are about to explain. Explain it. Ask a question only if a missing fact prevents a correct step.
        Never claim the learner completed an action without evidence. Use the learner's language.
        """;

    // Remove only stock standalone openings/closings; never cut a real instruction, formula, or warning.
    [GeneratedRegex(@"\A\s*(?:(?:sure(?: thing)?|certainly|absolutely|great question|good question|happy to help|I'd be happy to help|let's dive in)[!.:]\s*)+", RegexOptions.IgnoreCase)]
    private static partial Regex Opening();
    [GeneratedRegex(@"\s+(?:Let me know if you (?:have any questions|need (?:any |more |further )?help|need anything else)|Feel free to ask (?:any questions|if you need (?:more )?help))[!.]?\s*\z", RegexOptions.IgnoreCase)]
    private static partial Regex Closing();

    /// <summary>The language the learner wrote in, by its letters: Pip answers in it even when the app on screen uses
    /// another language. Null when it can't tell. Same rules as TeachingReply.language(of:) on Mac.</summary>
    internal static string? Language(string question)
    {
        int latin = 0, han = 0, kana = 0, hangul = 0;
        foreach (var c in question)
        {
            if (c is >= 'A' and <= 'Z' or >= 'a' and <= 'z') latin++;
            else if (c is >= '\u3040' and <= '\u30FF') kana++;
            else if (c is >= '\uAC00' and <= '\uD7AF') hangul++;
            else if (c is >= '\u3400' and <= '\u9FFF' or >= '\uF900' and <= '\uFAFF') han++;
        }
        if (kana > 0) return "Japanese";
        if (hangul > 0) return "Korean";
        if (han > 0) return han * 2 >= latin ? "Chinese" : "English";
        return latin >= 3 ? "English" : null;
    }

    /// <summary>The line added to a question that says which language to answer in.</summary>
    internal static string LanguageLine(string question) => Language(question) is { } language
        ? $" The learner wrote in {language}: answer in {language}, naming on-screen controls in {language} with their on-screen names in brackets."
        : "";

    internal static string Clean(string text)
    {
        var clean = Opening().Replace(text.Trim(), "");
        clean = Closing().Replace(clean, "").Trim();
        return clean.Length == 0 ? text.Trim() : clean;
    }
}
