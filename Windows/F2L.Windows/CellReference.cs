using System.Text.RegularExpressions;

namespace F2L.Windows;

internal sealed record CellReference(string Address, int Row, int Column)
{
    // ASCII-only edges, so a reference written straight after Chinese text ("圈出A1") is still found.
    private static readonly Regex CellPattern = new(@"(?<![A-Za-z0-9_!])\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})(?![A-Za-z0-9_])", RegexOptions.Compiled);

    internal static CellReference? Parse(string text)
    {
        var match = CellPattern.Match(text.Trim());
        if (!match.Success || match.Value.Length != text.Trim().Length) return null;
        var letters = match.Groups[1].Value.ToUpperInvariant();
        var column = letters.Aggregate(0, (value, letter) => value * 26 + letter - 'A' + 1);
        if (!int.TryParse(match.Groups[2].Value, out var row) || row > 1_048_576 || column > 16_384) return null;
        return new CellReference(letters + row, row, column);
    }

    internal static IReadOnlyList<CellReference> Find(string question) => CellPattern.Matches(question)
        .Select(match => Parse(match.Value)).OfType<CellReference>().DistinctBy(cell => cell.Address).ToArray();

    internal static bool MatchesRequest(CellReference proposed, IReadOnlyList<CellReference> requested) =>
        requested.Count == 0 || requested.Count == 1 && requested[0].Address == proposed.Address;

    internal static bool IsPointingOnly(string question)
    {
        if (Find(question).Count != 1 || !Regex.IsMatch(question, @"\b(circle|highlight|mark|locate|find|point|show)\b|圈|標記|标记", RegexOptions.IgnoreCase)) return false;
        var rest = CellPattern.Replace(question, " ");
        rest = Regex.Replace(rest, @"\b(please|can|could|would|you|circle|highlight|mark|locate|find|point|show|me|at|to|the|cell|in|on|excel|for)\b|圈出|圈|標記|标记|請|请", " ", RegexOptions.IgnoreCase);
        return Regex.IsMatch(rest, @"^[\s.,?!]*$");
    }
}
