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
    internal static string Compose(string question, ExcelContext? excel, LearnerProfile? profile = null, string? app = null,
        IEnumerable<string>? screenNames = null, AIToolLibrary? library = null, string? windowTitle = null,
        RecipeLibrary? recipes = null, string account = "") =>
        question + "\n\n(Learner's computer: Windows." + (string.IsNullOrEmpty(app) ? "" : $" The screenshot shows {app}.")
        + (excel is null ? "" : " " + excel.PromptLine) + TeachingReply.LanguageLine(question) + ")" + ScreenNames.Line(screenNames ?? [])
        + Reference(question, profile, app, library, windowTitle, recipes, account).Notes + (profile?.CoachingContext ?? "");

    /// <summary>What one question resolves to: the tools, the recipes, and the reference text those two produce.
    /// Compose builds the question from it, and the host uses the same recipes to check their on-screen names before
    /// pointing at them. Same order and wording as CoachClient.reference(...) on Mac.</summary>
    internal static (IReadOnlyList<AITool> Tools, IReadOnlyList<Recipe> Recipes, string Notes) Reference(string question,
        LearnerProfile? profile, string? app, AIToolLibrary? library, string? windowTitle, RecipeLibrary? recipes, string account)
    {
        // The tool is resolved from the app in front before the question's own words, so a bare "Copilot" in Word is
        // not answered with GitHub Copilot's coding notes.
        var tools = library?.Resolve(question, app, windowTitle) ?? [];
        var text = library?.ReferenceNotes(question, profile, tools) ?? "";
        var moment = new RecipeContext(question, app ?? "", windowTitle ?? "", account, profile);
        IReadOnlyList<Recipe> chosen = recipes is null || tools.Count == 0 ? [] : recipes.Select(moment, tools);
        // Nothing named and nothing on screen fits: propose the tool whose recipe the task asks for.
        // A tool the question names ("into an Excel table") doesn't count as part of the task.
        var named = library is null ? [] : RecipeLibrary.ToolWords(library.Mentioned(question));
        if (recipes is not null && library is not null
            && (QuestionIntentClassifier.Classify(question) == QuestionIntent.Procedural || RecipeLibrary.IsGettingStarted(question))
            && recipes.Suggest(moment, library.Tools, named) is { } suggested && chosen.All(recipe => recipe.Id != suggested.Id)
            && RecipeLibrary.TagHits(suggested, question, named) > (chosen.Count > 0 ? RecipeLibrary.TagHits(chosen[0], question, named) : 0)
            && library.Find(suggested.Tool) is { } tool)
        {
            tools = new[] { tool }.Concat(tools).ToList();
            return (tools, [suggested], library.ReferenceNotes(question, profile, tools) + RecipeLibrary.SuggestionNote(tool.Name) + recipes.Notes([suggested]));
        }
        if (recipes is null || tools.Count == 0) return (tools, [], text);
        if (chosen.Count > 0) return (tools, chosen, text + recipes.Notes(chosen));
        // Only a how-to question is told there is no recipe; a greeting or a quick fact needs no such warning.
        return (tools, [], QuestionIntentClassifier.Classify(question) == QuestionIntent.Procedural
            ? text + RecipeLibrary.NoRecipeNote : text);
    }
}
