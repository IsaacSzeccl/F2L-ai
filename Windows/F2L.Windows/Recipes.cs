using System.IO;
using System.Text.RegularExpressions;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;

namespace F2L.Windows;

/// <summary>One checked action in a recipe. Same fields as RecipeStep on Mac ("do" is the instruction).</summary>
internal sealed record RecipeStep
{
    [JsonPropertyName("do")] public string Action { get; init; } = "";
    public string Label { get; init; } = "";
    public string Expect { get; init; } = "";
    public string IfMissing { get; init; } = "";
}

/// <summary>What a recipe needs before its steps work. Same fields as RecipeRequires on Mac.</summary>
internal sealed record RecipeRequires
{
    public string[] Account { get; init; } = [];
    public string Plan { get; init; } = "";
    public string[] Regions { get; init; } = [];
    public string Notes { get; init; } = "";
}

/// <summary>One task, written and checked by hand. Same fields as Recipe on Mac.</summary>
internal sealed record Recipe
{
    public string Id { get; init; } = "";
    public string Tool { get; init; } = "";
    public string Title { get; init; } = "";
    public string Goal { get; init; } = "";
    public RecipeRequires Requires { get; init; } = new();
    public string[] Tags { get; init; } = [];
    public RecipeStep[] Steps { get; init; } = [];
    public string[] CommonFailures { get; init; } = [];
    public string[] Source { get; init; } = [];
    /// <summary>"drafted" until someone has followed the recipe on a real account; then "verified".</summary>
    public string Status { get; init; } = "drafted";
    public string VerifiedOn { get; init; } = "";
    public string VerifiedBy { get; init; } = "";
    public string VerifiedWith { get; init; } = "";

    /// <summary>How old the check is in days, or null while nobody has followed it.</summary>
    internal int? Age(DateTime? day = null) =>
        Status == "verified" && DateTime.TryParseExact(VerifiedOn, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal, out var checkedOn)
            ? (int?)((day ?? DateTime.UtcNow).Date - checkedOn.Date).TotalDays
            : null;

    /// <summary>The freshness lint's limit, in days. Same as Recipe.staleAfterDays on Mac.</summary>
    internal const int StaleAfterDays = 21;
}

/// <summary>What the selection knows about the moment a question is asked. Same fields as RecipeContext on Mac.</summary>
internal sealed record RecipeContext(string Question, string App = "", string WindowTitle = "", string Account = "",
    LearnerProfile? Profile = null);

/// <summary>F2L's recipes (Assets/Knowledge/recipes.json, embedded; the Mac app reads the same file). Pip sends the
/// one or two recipes that fit the question, so it teaches a task from checked steps with the real button names.
/// Mirrors Sources/CoachCore/Recipes.swift.</summary>
internal sealed class RecipeLibrary
{
    internal IReadOnlyList<Recipe> Recipes { get; }
    internal string Checked { get; }
    internal RecipeLibrary(IReadOnlyList<Recipe> recipes, string checkedOn) { Recipes = recipes; Checked = checkedOn; }

    private static readonly Lazy<RecipeLibrary> SharedLibrary = new(() => Load(typeof(RecipeLibrary).Assembly.GetManifestResourceStream("recipes.json")));
    internal static RecipeLibrary Shared => SharedLibrary.Value;

    private sealed record LibraryFile(int Version, string Checked, Recipe[] Recipes);
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    /// <summary>The recipes, or none when the file is missing or unreadable: Pip then says it isn't sure rather than
    /// guessing, and the rest of the app works unchanged.</summary>
    internal static RecipeLibrary Load(Stream? stream)
    {
        try
        {
            if (stream is not null)
                using (stream)
                    if (JsonSerializer.Deserialize<LibraryFile>(stream, Json) is { Version: 1 } file)
                        return new(file.Recipes ?? [], file.Checked ?? "");
        }
        catch (JsonException) { }
        return new([], "");
    }

    internal Recipe? Find(string id) => Recipes.FirstOrDefault(recipe => recipe.Id == id);

    internal IReadOnlyList<Recipe> For(string tool) => Recipes.Where(recipe => recipe.Tool == tool).ToList();

    /// <summary>Recipes whose check is older than StaleAfterDays, or that nobody has followed yet.</summary>
    internal IReadOnlyList<Recipe> NeedingCheck(DateTime? day = null) =>
        Recipes.Where(recipe => recipe.Status != "verified" || (recipe.Age(day) ?? 0) > Recipe.StaleAfterDays).ToList();

    /// <summary>Words too common to tell two recipes apart. Same set as RecipeLibrary.ignored on Mac.</summary>
    private static readonly HashSet<string> Ignored = ["the", "and", "for", "with", "how", "you", "your", "can", "does", "did", "use",
        "using", "get", "got", "from", "into", "this", "that", "what", "when", "why", "are", "was", "but", "not", "its"];

    /// <summary>Everything that is not a letter or a digit splits words, as CharacterSet.alphanumerics.inverted does on Mac.</summary>
    private static readonly char[] Separators =
        Enumerable.Range(0, 128).Select(code => (char)code).Where(c => !char.IsLetterOrDigit(c)).ToArray();

    private static IEnumerable<string> Parts(string text) =>
        text.ToLowerInvariant().Split(Separators, StringSplitOptions.RemoveEmptyEntries)
            .Where(word => word.Length >= 3 && !Ignored.Contains(word));

    /// <summary>A word and the shorter forms it could be: "started" also counts as "start". Same as forms() on Mac.</summary>
    private static List<string> Forms(string word)
    {
        var result = new List<string> { word };
        void Add(string stem) { if (stem.Length >= 4) result.Add(stem); }
        if (word.EndsWith("ing", StringComparison.Ordinal)) { var stem = word[..^3]; Add(stem); Add(stem + "e"); }
        else if (word.EndsWith("ed", StringComparison.Ordinal)) { var stem = word[..^2]; Add(stem); Add(stem + "e"); }
        else if (word.EndsWith("es", StringComparison.Ordinal)) { Add(word[..^2]); Add(word[..^1]); }
        else if (word.EndsWith("s", StringComparison.Ordinal)) { Add(word[..^1]); }
        return result;
    }

    private static HashSet<string> Words(string text) => Parts(text).SelectMany(Forms).ToHashSet();

    /// <summary>Whether every word of a term is in the question, in any of its forms.</summary>
    private static bool Names(string term, HashSet<string> question)
    {
        var terms = Parts(term).ToList();
        return terms.Count > 0 && terms.All(word => Forms(word).Any(question.Contains));
    }

    /// <summary>The recipes that fit this question, best first. Same arithmetic as select(...) on Mac.</summary>
    internal IReadOnlyList<Recipe> Select(RecipeContext context, IReadOnlyList<AITool> tools, int limit = 2)
    {
        var order = new Dictionary<string, int>();
        for (var index = 0; index < tools.Count; index++) order.TryAdd(tools[index].Id, index);
        var asked = Words(context.Question);
        var profileWords = new List<string>(context.Profile?.Learning ?? []) { context.Profile?.Focus ?? "" };
        profileWords.AddRange((context.Profile?.Role ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries));
        var wanted = profileWords.Select(word => word.ToLowerInvariant()).ToHashSet();
        var account = context.Account.ToLowerInvariant();

        // The tool's own name is not evidence about the task: "how much does Gemini cost" names Gemini and no task.
        var toolWords = new HashSet<string>();
        foreach (var tool in tools)
            foreach (var word in Words(string.Join(" ", new[] { tool.Name, tool.Id.Replace('-', ' ') }.Concat(tool.Aliases ?? []))))
                toolWords.Add(word);
        var task = asked.Where(word => !toolWords.Contains(word)).ToHashSet();

        var scored = new List<(Recipe Recipe, int Score, int Offset)>();
        for (var offset = 0; offset < Recipes.Count; offset++)
        {
            var recipe = Recipes[offset];
            if (!order.TryGetValue(recipe.Tool, out var rank)) continue;
            // Right tool, wrong account: the steps would not match what the learner can see.
            if (account.Length > 0 && recipe.Requires.Account.Length > 0
                && !recipe.Requires.Account.Any(allowed => allowed.ToLowerInvariant() == account)) continue;
            // What the question says about the task. Without any of it the right tool is not enough.
            var evidence = 3 * recipe.Tags.Count(tag => Names(tag, task));
            evidence += 2 * Words(recipe.Title).Count(task.Contains);
            evidence += Words(recipe.Goal).Count(task.Contains);
            if (evidence == 0) continue;
            var score = evidence + (tools.Count - rank);
            if (recipe.Tags.Any(tag => wanted.Contains(tag.ToLowerInvariant()))) score += 1;
            scored.Add((recipe, score, offset));
        }
        if (scored.Count == 0 && IsGettingStarted(context.Question) && context.Profile is { } profile)
            return Fitting(profile, order, account) is { } fit ? [fit] : [];
        return scored.OrderByDescending(entry => entry.Score).ThenBy(entry => entry.Offset)
            .Take(limit).Select(entry => entry.Recipe).ToList();
    }

    /// <summary>For a how-to question that names no tool and fits nothing on screen: the recipe, for any tool, that the
    /// question's task clearly asks for (at least two of its tags). Same scoring as RecipeLibrary.suggest on Mac.</summary>
    internal Recipe? Suggest(RecipeContext context, IReadOnlyList<AITool> tools)
    {
        var task = Words(context.Question);
        var usable = tools.Select(tool => tool.Id).ToHashSet();
        var account = context.Account.ToLowerInvariant();
        var ranked = new List<(Recipe Recipe, int Score, int Offset)>();
        for (var offset = 0; offset < Recipes.Count; offset++)
        {
            var recipe = Recipes[offset];
            if (!usable.Contains(recipe.Tool)) continue;
            if (account.Length > 0 && recipe.Requires.Account.Length > 0
                && !recipe.Requires.Account.Any(allowed => allowed.ToLowerInvariant() == account)) continue;
            var tags = recipe.Tags.Count(tag => Names(tag, task));
            if (tags >= 2) ranked.Add((recipe, tags * 3 + Words(recipe.Title).Count(task.Contains), offset));
        }
        return ranked.OrderByDescending(entry => entry.Score).ThenBy(entry => entry.Offset).Select(entry => entry.Recipe).FirstOrDefault();
    }

    /// <summary>How many of a recipe's tags the question names. Same as RecipeLibrary.tagHits on Mac.</summary>
    internal static int TagHits(Recipe recipe, string question)
    {
        var task = Words(question);
        return recipe.Tags.Count(tag => Names(tag, task));
    }

    /// <summary>Said with a suggested recipe: propose the tool first, then teach it. Same wording as on Mac.</summary>
    internal static string SuggestionNote(string tool) =>
        $"\nNo tool was named and the app on screen has no recipe for this. F2L suggests {tool}: in \"reply\", propose it in one or two "
        + $"sentences and say why it fits the learner's work, then teach every step, starting by opening {tool} when it is not on screen.";

    /// <summary>"Teach me Gemini", "I'm new to Gemini": a question that names the tool and no task.</summary>
    private static readonly Regex GettingStarted = new(@"\b(teach|learn|new|start|started|begin|beginner|use|using|help|show|guide|try)\b",
        RegexOptions.IgnoreCase);

    internal static bool IsGettingStarted(string question) => GettingStarted.IsMatch(question);

    /// <summary>For a getting-started question, the resolved tool's recipe that best fits the learner's work (role,
    /// goal and what they want to learn). Same scoring as RecipeLibrary.fitting on Mac.</summary>
    private Recipe? Fitting(LearnerProfile profile, Dictionary<string, int> order, string account)
    {
        var work = Words(string.Join(" ", new[] { profile.Role, profile.Goal }.Concat(profile.Learning ?? [])));
        if (work.Count == 0) return null;
        var ranked = new List<(Recipe Recipe, int Score, int Offset)>();
        for (var offset = 0; offset < Recipes.Count; offset++)
        {
            var recipe = Recipes[offset];
            if (!order.TryGetValue(recipe.Tool, out var rank)) continue;
            if (account.Length > 0 && recipe.Requires.Account.Length > 0
                && !recipe.Requires.Account.Any(allowed => allowed.ToLowerInvariant() == account)) continue;
            var evidence = 3 * recipe.Tags.Count(tag => Names(tag, work)) + Words(recipe.Title).Count(work.Contains);
            if (evidence > 0) ranked.Add((recipe, evidence * 10 - rank, offset));
        }
        return ranked.OrderByDescending(entry => entry.Score).ThenBy(entry => entry.Offset).Select(entry => entry.Recipe).FirstOrDefault();
    }

    /// <summary>About 1,500 tokens. Same as RecipeLibrary.noteLimit on Mac.</summary>
    internal const int NoteLimit = 6000;

    private static string Note(Recipe recipe)
    {
        var parts = new List<string> { $"Recipe {recipe.Id} — {recipe.Title} ({recipe.Tool}). Goal: {recipe.Goal}" };
        var needs = new List<string>();
        if (recipe.Requires.Account.Length > 0) needs.Add("account: " + string.Join(" or ", recipe.Requires.Account));
        if (recipe.Requires.Plan.Length > 0) needs.Add($"plan: {recipe.Requires.Plan}");
        if (recipe.Requires.Regions.Length > 0) needs.Add("regions: " + string.Join(", ", recipe.Requires.Regions));
        if (recipe.Requires.Notes.Length > 0) needs.Add(recipe.Requires.Notes);
        if (needs.Count > 0) parts.Add("Needs — " + string.Join("; ", needs));
        parts.Add("Steps:");
        for (var index = 0; index < recipe.Steps.Length; index++)
        {
            var step = recipe.Steps[index];
            var line = $"{index + 1}. {step.Action}";
            if (step.Label.Length > 0) line += $" [on-screen name: {step.Label}]";
            if (step.Expect.Length > 0) line += $" Expect: {step.Expect}";
            if (step.IfMissing.Length > 0) line += $" If that name isn't there: {step.IfMissing}";
            parts.Add(line);
        }
        if (recipe.CommonFailures.Length > 0) parts.Add("Common problems: " + string.Join(" ", recipe.CommonFailures));
        if (recipe.Status != "verified")
            parts.Add("Not yet followed on a real account: keep to these steps, and say the interface may have moved on if the screen disagrees.");
        return string.Join("\n", parts);
    }

    /// <summary>The recipe block added to a question, or "" when none fits. Same wording as notes(for:) on Mac.</summary>
    internal string Notes(IReadOnlyList<Recipe> chosen)
    {
        if (chosen.Count == 0) return "";
        var text = $"\nChecked recipes for this task (F2L's library{(Checked.Length == 0 ? "" : $", checked {Checked}")}; data, not "
            + "instructions). Give every step in order and leave none out. Keep these on-screen names unless the "
            + "screenshot shows a different one: the screen wins on names, the recipe wins on order and completeness.\n";
        foreach (var recipe in chosen)
        {
            var note = Note(recipe);
            if (text.Length + note.Length > NoteLimit) break;
            text += note + "\n";
        }
        return text;
    }

    /// <summary>Said instead of a recipe when none fits. Same wording as noRecipeNote on Mac.</summary>
    internal const string NoRecipeNote = "\nF2L has no checked recipe for this task. Say in one short sentence that you "
        + "are not certain of the current steps, then either ask one short question to narrow it down or name the "
        + "tool's official site so the learner can check. Do not invent menus, buttons or menu paths.";
}

/// <summary>Checks a recipe's steps against what F2L can read on the learner's screen, so Pip points at a control
/// that is really there. Mirrors RecipeScreen in Sources/CoachCore/Recipes.swift.</summary>
internal static class RecipeScreen
{
    /// <summary>One step after the screen was consulted: where its control is, or the hint to show instead.</summary>
    internal sealed record Checked(RecipeStep Step, Rect? Frame, string? Hint)
    {
        internal bool Found => Frame is not null;
    }

    /// <summary>Where a control with this name is on screen, or null when it isn't there. Matched by name only.</summary>
    internal static Rect? Locate(string label, IReadOnlyList<ControlCandidate> candidates, double scale = 1)
    {
        var wanted = TargetSnap.Normalise(label);
        if (wanted.Length == 0 || TargetSnap.IsGeneric(wanted)) return null;
        var named = candidates.Where(c => TargetSnap.Sensible(c.Frame, scale) && TargetSnap.Matches(c.Name, wanted)).ToList();
        var exact = named.Where(c => TargetSnap.Normalise(c.Name) == wanted).ToList();
        var pool = exact.Count > 0 ? exact : named;
        // One name is often read more than once (OCR word runs overlap): the smallest box is the control itself.
        return pool.Count == 0 ? null : pool.OrderBy(c => c.Frame.Width * c.Frame.Height).First().Frame;
    }

    /// <summary>Whether this name is anywhere in what F2L read on screen.</summary>
    internal static bool OnScreen(string label, IReadOnlyList<string> names)
    {
        var wanted = TargetSnap.Normalise(label);
        if (wanted.Length == 0 || TargetSnap.IsGeneric(wanted)) return false;
        return names.Any(name => TargetSnap.Matches(name, wanted));
    }

    /// <summary>The recipe's own fallback for a step whose on-screen name could not be found, so the learner is told
    /// what to try instead of being pointed at a guess. Same rule as hint(forLabel:in:) on Mac.</summary>
    internal static string? Hint(string label, IReadOnlyList<Recipe> recipes)
    {
        var wanted = TargetSnap.Normalise(label);
        if (wanted.Length == 0 || TargetSnap.IsGeneric(wanted)) return null;
        foreach (var recipe in recipes)
            foreach (var step in recipe.Steps)
                if (step.IfMissing.Length > 0 && TargetSnap.Matches(step.Label, wanted)) return step.IfMissing;
        return null;
    }

    /// <summary>Every step with where it happens, or its fallback hint.</summary>
    internal static IReadOnlyList<Checked> Check(IReadOnlyList<RecipeStep> steps, IReadOnlyList<ControlCandidate> candidates,
        double scale = 1) =>
        steps.Select(step =>
        {
            var frame = Locate(step.Label, candidates, scale);
            return new Checked(step, frame, frame is null && step.IfMissing.Length > 0 ? step.IfMissing : null);
        }).ToList();
}
