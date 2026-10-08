using System.Text.RegularExpressions;

namespace F2L.Windows;

internal enum StepState { NotCheckable, Done, Missing }

/// <summary>Whether the learner's real Excel selection already does what a step asks. Only steps about selecting or
/// clicking cells can be checked; typing, menus and formulas are left to the learner's "Done".</summary>
internal static partial class StepCheck
{
    [GeneratedRegex(@"\b(select|click|drag|highlight|choose|hold|extend)\b", RegexOptions.IgnoreCase)] private static partial Regex Action();
    [GeneratedRegex(@"\b(command|cmd|ctrl|control)\b|⌘", RegexOptions.IgnoreCase)] private static partial Regex Adding();
    [GeneratedRegex(@"=\S+")] private static partial Regex Formula();
    [GeneratedRegex(@"(?<![A-Za-z0-9_!])\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})(?:\s*(?::|-|–|\bto\b|\bthrough\b)\s*\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6}))?(?![A-Za-z0-9_])", RegexOptions.IgnoreCase)]
    private static partial Regex Reference();

    private readonly record struct Area(int Top, int Left, int Bottom, int Right)
    {
        internal bool Covers(Area other) => Left <= other.Left && Right >= other.Right && Top <= other.Top && Bottom >= other.Bottom;
    }

    private static Area? ToArea(string address)
    {
        var parts = address.Split(':');
        if (parts.Length is < 1 or > 2 || CellReference.Parse(parts[0]) is not { } a) return null;
        if ((parts.Length == 2 ? CellReference.Parse(parts[1]) : a) is not { } b) return null;
        return new Area(Math.Min(a.Row, b.Row), Math.Min(a.Column, b.Column), Math.Max(a.Row, b.Row), Math.Max(a.Column, b.Column));
    }

    /// <summary>The cells and ranges a step names, in order, as "A1" or "A1:A4". Formulas are ignored.</summary>
    internal static IReadOnlyList<string> References(string step)
    {
        var text = Formula().Replace(step, " ");
        var seen = new HashSet<string>();
        var found = new List<string>();
        foreach (Match match in Reference().Matches(text))
        {
            var address = (match.Groups[1].Value + match.Groups[2].Value).ToUpperInvariant();
            if (match.Groups[3].Success && match.Groups[4].Success) address += ":" + (match.Groups[3].Value + match.Groups[4].Value).ToUpperInvariant();
            if (ToArea(address) is not null && seen.Add(address)) found.Add(address);
        }
        return found;
    }

    /// <summary><paramref name="earlier"/> are the steps before this one: when this step adds to the selection with
    /// Command or Ctrl, the cells they selected must still be selected too.</summary>
    internal static (StepState State, IReadOnlyList<string> Missing) Check(string step, IReadOnlyList<string> earlier, IReadOnlyList<string> selected)
    {
        var wanted = References(step).ToList();
        if (wanted.Count == 0 || !Action().IsMatch(step)) return (StepState.NotCheckable, []);
        if (Adding().IsMatch(step))
        {
            var kept = earlier.Where(previous => Action().IsMatch(previous)).SelectMany(References).Where(address => !wanted.Contains(address)).ToList();
            wanted = [.. kept, .. wanted];
        }
        var areas = selected.Select(ToArea).OfType<Area>().ToArray();
        var missing = wanted.Where(address => ToArea(address) is { } needed && !areas.Any(area => area.Covers(needed))).ToArray();
        return missing.Length == 0 ? (StepState.Done, []) : (StepState.Missing, missing);
    }
}
