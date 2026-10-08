namespace F2L.Windows;

internal sealed record ExcelContext(string Sheet, IReadOnlyList<string> Areas, string ActiveCell)
{
    internal static ExcelContext? Parse(string sheet, string selection, string activeCell)
    {
        var areas = selection.Replace("$", "").Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        return areas.Length == 0 ? null : new(sheet.Trim(), areas, activeCell.Replace("$", "").Trim());
    }
    internal string DisplayLine => $"Excel has selected {string.Join(", ", Areas)} · {Sheet}";
    internal string PromptLine => $"Excel reports (exact, read from Excel, not from the screenshot): sheet \"{Sheet}\"; selected cells {string.Join(", ", Areas)} ({(Areas.Count == 1 ? "1 area" : $"{Areas.Count} separate areas")}); active cell {ActiveCell}.";
    internal static string Compose(string question, ExcelContext? excel) => question + "\n\n(Learner's computer: Windows." + (excel is null ? "" : " " + excel.PromptLine) + ")";
}
