using System.Windows;
using System.Windows.Automation;

namespace F2L.Windows;

/// <summary>A real control another app reports through UI Automation: its frame in physical screen pixels and its name.</summary>
internal sealed record ControlCandidate(Rect Frame, string Name);

/// <summary>Turns the model's rough place on a screenshot into the real control, so Pip points at the actual button,
/// tab or menu. Mirrors Sources/CoachCore/TargetSnap.swift.</summary>
internal static class TargetSnap
{
    internal static readonly HashSet<string> Generic = ["", "next step", "here", "this", "button", "target", "cell"];
    /// <summary>Whether a label names nothing in particular ("Next step", "here").</summary>
    internal static bool IsGeneric(string label) => Generic.Contains(Normalise(label));
    private static readonly HashSet<string> Trailing = ["tab", "button", "menu", "icon", "option", "command", "control"];

    /// <summary>"Insert tab" → "insert"; "Pie Chart button…" → "pie chart".</summary>
    internal static string Normalise(string text)
    {
        var words = new string(text.ToLowerInvariant().Select(c => char.IsLetterOrDigit(c) || char.IsWhiteSpace(c) ? c : ' ').ToArray())
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).ToList();
        while (words.Count > 1 && Trailing.Contains(words[^1])) words.RemoveAt(words.Count - 1);
        return string.Join(' ', words);
    }

    internal static bool Matches(string name, string label)
    {
        name = Normalise(name);
        if (name.Length == 0) return false;
        if (name == label) return true;
        // Chinese and Japanese have no spaces and short words (新增, 設定): one inside the other counts.
        if ((IsWideScript(label) || IsWideScript(name)) && Math.Min(name.Length, label.Length) >= 2)
            // Spaces mean little between Chinese words. A fragment of a long label (記錄 inside 為技能命名，例如「會議記錄
            // 摘要工具」, or Gemini inside 問問 Gemini) is not the control.
            var n = name.Replace(" ", ""); var l = label.Replace(" ", "");
            return n.Contains(l, StringComparison.Ordinal) || (l.Contains(n, StringComparison.Ordinal) && n.Length * 4 > l.Length * 3);
        // Every meaningful word of one is in the other: "pie chart" matches "Insert Pie or Doughnut Chart".
        static HashSet<string> Words(string text) => text.Split(' ').Where(word => word.Length >= 3).ToHashSet();
        var nameWords = Words(name); var labelWords = Words(label);
        // A shorter name must still cover most of the label: "Gemini" alone is not "Customize Gemini".
        return nameWords.Count > 0 && labelWords.Count > 0
            && (labelWords.IsSubsetOf(nameWords) || (nameWords.IsSubsetOf(labelWords) && nameWords.Count * 3 >= labelWords.Count * 2));
    }

    /// <summary>Han, kana or hangul in the text.</summary>
    internal static bool IsWideScript(string text) => text.Any(c =>
        (c >= '\u3040' && c <= '\u30FF') || (c >= '\u3400' && c <= '\u9FFF') || (c >= '\uAC00' && c <= '\uD7AF') || (c >= '\uF900' && c <= '\uFAFF'));

    internal static bool Sensible(Rect frame, double scale) =>
        frame.Width >= 6 * scale && frame.Height >= 6 * scale && frame.Width <= 700 * scale && frame.Height <= 300 * scale;

    /// <summary>The control the model meant, or null to keep its own (approximate) box.</summary>
    /// <remarks>Words read off the screen are matched by name only (<paramref name="byPosition"/> false): a stray "2"
    /// under the model's spot is not the Fill button.</remarks>
    internal static Rect? Snap(Rect? box, string label, IReadOnlyList<ControlCandidate> candidates, double scale = 1, bool byPosition = true)
    {
        label = Normalise(label);
        var usable = candidates.Where(candidate => Sensible(candidate.Frame, scale)).ToArray();
        double Distance(Rect frame) => box is { } b ? Math.Sqrt(Math.Pow(frame.X + frame.Width / 2 - (b.X + b.Width / 2), 2) +
            Math.Pow(frame.Y + frame.Height / 2 - (b.Y + b.Height / 2), 2)) : 0;
        if (!Generic.Contains(label))
        {
            var named = usable.Where(candidate => Matches(candidate.Name, label)).ToArray();
            var exact = named.Where(candidate => Normalise(candidate.Name) == label).ToArray();
            var pool = exact.Length > 0 ? exact : named;
            if (box is { } near)
            {
                var reach = Math.Max(260 * scale, Math.Max(near.Width, near.Height) * 3);
                var best = pool.Where(candidate => Distance(candidate.Frame) <= reach).OrderBy(candidate => Distance(candidate.Frame)).FirstOrDefault();
                if (best is not null) return best.Frame;
            }
            else if (pool.Length == 1) return pool[0].Frame;
        }
        if (!byPosition || box is not { } spot) return null;
        var center = new Point(spot.X + spot.Width / 2, spot.Y + spot.Height / 2);
        var area = Math.Max(1, spot.Width * spot.Height);
        return usable.Where(candidate => candidate.Frame.Contains(center))
            .Where(candidate => candidate.Frame.Width * candidate.Frame.Height / area is >= 0.2 and <= 5)
            .OrderBy(candidate => candidate.Frame.Width * candidate.Frame.Height).Select(candidate => (Rect?)candidate.Frame).FirstOrDefault();
    }

    /// <summary>The ellipse Pip circles a target with: it passes just outside the target's corners.</summary>
    internal static Rect Circle(Rect target, double margin = 5)
    {
        var a = target.Width / 2 * Math.Sqrt(2) + margin;
        var b = target.Height / 2 * Math.Sqrt(2) + margin;
        return new Rect(target.X + target.Width / 2 - a, target.Y + target.Height / 2 - b, a * 2, b * 2);
    }

    /// <summary>The named controls of <paramref name="window"/> (UI Automation, read-only). Runs on its own thread
    /// with a time limit, so a slow app never stalls Pip. Name, place and visibility come back with the search itself
    /// (a cache request), instead of three more calls into the app per control.</summary>
    internal static async Task<IReadOnlyList<ControlCandidate>> ControlsAsync(IntPtr window, CancellationToken token, double seconds = 2)
    {
        var completion = new TaskCompletionSource<IReadOnlyList<ControlCandidate>>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            var found = new List<ControlCandidate>();
            try
            {
                var root = AutomationElement.FromHandle(window);
                var types = new[] { ControlType.Button, ControlType.TabItem, ControlType.MenuItem, ControlType.SplitButton, ControlType.CheckBox,
                    ControlType.RadioButton, ControlType.ComboBox, ControlType.Hyperlink, ControlType.ListItem, ControlType.Edit, ControlType.Text };
                var condition = new OrCondition(types.Select(type => (System.Windows.Automation.Condition)new PropertyCondition(AutomationElement.ControlTypeProperty, type)).ToArray());
                var cache = new CacheRequest { AutomationElementMode = AutomationElementMode.None, TreeScope = TreeScope.Element };
                cache.Add(AutomationElement.NameProperty);
                cache.Add(AutomationElement.BoundingRectangleProperty);
                cache.Add(AutomationElement.IsOffscreenProperty);
                AutomationElementCollection elements;
                using (cache.Activate()) elements = root.FindAll(TreeScope.Descendants, condition);
                foreach (AutomationElement element in elements)
                {
                    if (found.Count >= 4000) break;
                    try
                    {
                        var name = element.Cached.Name;
                        var frame = element.Cached.BoundingRectangle;
                        if (!string.IsNullOrWhiteSpace(name) && !frame.IsEmpty && !element.Cached.IsOffscreen) found.Add(new(frame, name));
                    }
                    catch (Exception error) when (error is ElementNotAvailableException or InvalidOperationException) { }
                }
            }
            catch (Exception) { }
            completion.TrySetResult(found);
        }) { IsBackground = true, Name = "F2L control lookup" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        try { return await completion.Task.WaitAsync(TimeSpan.FromSeconds(seconds), token); }
        catch (TimeoutException) { return []; }
    }
}
