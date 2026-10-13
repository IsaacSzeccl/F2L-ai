using System.Text.RegularExpressions;

namespace F2L.Windows;

/// <summary>What a step asks the learner to get to, when F2L can see it happen without a click on a circle: an app in
/// front ("Open your browser", "Open Excel") or a website open in the browser ("Go to chatgpt.com"). MainWindow checks
/// the app in front and its window title twice a second; Done stays for everything else. Mirrors StepGoal.swift.</summary>
internal sealed partial record StepGoal(StepGoal.Kind Type, IReadOnlyList<string> Names)
{
    internal enum Kind { Browser, App, Site }

    /// <summary>Browsers by their app (process) name, Mac and Windows.</summary>
    internal static readonly string[] Browsers = ["safari", "chrome", "edge", "firefox", "arc", "brave", "opera", "chromium", "vivaldi", "duckduckgo"];

    [GeneratedRegex(@"\b((?:[a-z0-9-]+\.)+(?:com|ai|so|app|dev|io|org|net|co|google|cn|me|new|chat))\b", RegexOptions.IgnoreCase)]
    private static partial Regex Domain();
    [GeneratedRegex(@"\b(?i:open|launch|start|switch to|go to|bring up)\s+(?i:up\s+)?(?i:your\s+|the\s+|a\s+)?([A-Z][\w.+-]*(?:\s+[A-Z0-9][\w.+-]*){0,2})")]
    private static partial Regex Opening();
    [GeneratedRegex(@"\b(?:open|launch|start|switch to|use)\b[^.]*\b(?:browser|web browser)\b", RegexOptions.IgnoreCase)]
    private static partial Regex BrowserWords();

    /// <summary>The goal a step names, or null when only the learner can say it is done.</summary>
    internal static StepGoal? Of(string step, AIToolLibrary? library = null)
    {
        if (Domain().Match(step) is { Success: true } site)
        {
            var host = site.Groups[1].Value.ToLowerInvariant().Replace("www.", "");
            var names = new List<string> { host, host.Split('.')[0] };
            if (library?.Tools.FirstOrDefault(tool => Uri.TryCreate(tool.Url, UriKind.Absolute, out var url) && url.Host.Replace("www.", "") == host) is { } tool)
                names.Add(tool.Name.Split(" (")[0].ToLowerInvariant());
            return new(Kind.Site, names.Where(name => name.Length >= 2).ToList());
        }
        if (BrowserWords().IsMatch(step)) return new(Kind.Browser, []);
        if (Opening().Match(step) is { Success: true } opening)
        {
            var name = opening.Groups[1].Value.ToLowerInvariant().Trim('.', ',', ';', ':', '!', '?');
            if (Browsers.Any(name.Contains)) return new(Kind.Browser, []);
            // "Open the Insert tab" names a place inside the app, not an app.
            string[] places = ["tab", "menu", "page", "panel", "dialog", "window", "settings", "sidebar", "file", "folder", "list", "box"];
            if (!places.Any(place => step.ToLowerInvariant().Contains($"{name} {place}")) && name.Length >= 3) return new(Kind.App, [name]);
        }
        return null;
    }

    /// <summary>Whether the app in front (and its window title) shows the goal reached.</summary>
    internal bool IsMet(string app, string title)
    {
        app = app.ToLowerInvariant(); title = title.ToLowerInvariant();
        var inBrowser = Browsers.Any(app.Contains);
        return Type switch
        {
            Kind.Browser => inBrowser,
            Kind.App => Names.Any(name => app.Contains(name) || (name.Contains(app) && app.Length >= 3)),
            _ => inBrowser && Names.Any(title.Contains),
        };
    }
}
