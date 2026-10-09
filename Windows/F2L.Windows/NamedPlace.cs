using System.Text.RegularExpressions;

namespace F2L.Windows;

/// <summary>The AI sometimes names the place in words but leaves out where it is ("Click the Japan tile in the Recents
/// row." with no target). Then F2L still circles it: it takes the name the instruction points at and finds it on
/// screen itself (screen text and UI Automation). Mirrors Sources/CoachCore/NamedPlace.swift.</summary>
internal static partial class NamedPlace
{
    [GeneratedRegex(@"\b(double-click|right-click|click|tap|select|choose|open|press|pick|go to|switch to|turn on|turn off|toggle|check|uncheck|find|type in|type into)\b", RegexOptions.IgnoreCase)]
    private static partial Regex ActionWord();
    [GeneratedRegex("[\"“'‘]([^\"”'’\\n]{1,40})[\"”'’]")]
    private static partial Regex Quoted();
    /// <summary>Keyboard keys are pressed, not circled.</summary>
    private static readonly HashSet<string> Keys = ["command", "cmd", "ctrl", "control", "shift", "option", "alt", "return", "enter", "escape", "esc",
        "space", "delete", "backspace", "fn", "windows", "win", "tab"];
    private static readonly HashSet<string> Filler = ["the", "a", "an", "on", "your", "this", "that", "its", "it", "cell", "button", "tab", "menu", "icon"];

    /// <summary>The name of the thing an instruction tells the learner to act on, or null when it names nothing on screen.</summary>
    internal static string? Label(string text)
    {
        var verb = ActionWord().Match(text);
        if (!verb.Success) return null;
        var rest = text[(verb.Index + verb.Length)..];
        var quote = Quoted().Match(rest);
        if (quote.Success && quote.Groups[1].Value.Trim().Length > 0) return quote.Groups[1].Value.Trim();
        var run = new List<string>();
        var tokens = rest.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        for (var index = 0; index < tokens.Length; index++)
        {
            var raw = tokens[index];
            var word = raw.Trim(raw.Where(c => char.IsPunctuation(c) && c != '+').Distinct().ToArray());
            var ends = ".,;:!?".Contains(raw[^1]);
            var isKey = word.ToLowerInvariant().Split('+').Any(Keys.Contains);
            var named = !isKey && word.Length > 0 && (char.IsUpper(word[0]) || CellReference.Parse(word) is not null);
            if (named) run.Add(word);
            else if (run.Count > 0 || isKey || index >= 6) break;
            else if (!Filler.Contains(word.ToLowerInvariant()) && index >= 3) break;
            if (ends || run.Count == 4) break;
        }
        return run.Count == 0 ? null : string.Join(" ", run);
    }

    /// <summary>A place with no position: the host finds it on screen by its name (or checks it with Excel when it is a cell).</summary>
    internal static ScreenTarget? Target(string text)
    {
        if (Label(text) is not { } label) return null;
        // A cell ("A4") or a range ("A1:A4") is checked with Excel from its first cell, like the AI's own cell targets.
        var parts = label.Split(':');
        var cell = parts.Length <= 2 && parts.All(part => CellReference.Parse(part) is not null) ? CellReference.Parse(parts[0])?.Address : null;
        return new ScreenTarget(0, 0, 0, 0, label, cell);
    }
}
