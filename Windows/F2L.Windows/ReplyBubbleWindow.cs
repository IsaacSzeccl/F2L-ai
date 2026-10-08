using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace F2L.Windows;

/// <summary>Pip's reply card beside the character: words appear one by one, and a lesson moves one step at a time with
/// Done / Show me again / I'm stuck and ticks Excel steps by itself.
/// Mirrors Sources/F2L/ReplyBubble.swift. It never takes keyboard focus from the app being taught.</summary>
internal sealed partial class ReplyBubbleWindow : Window
{
    private enum PageKind { Text, Step, Finished }
    private sealed record Page(PageKind Kind, string Text = "", int Step = 0, bool Last = false);

    private static readonly Brush Ink = Frozen(Color.FromRgb(36, 37, 41));
    private static readonly Brush Good = Frozen(Color.FromRgb(55, 141, 116));
    private static readonly Brush Warn = Frozen(Color.FromRgb(193, 142, 56));
    private static readonly Brush Soft = Frozen(Color.FromRgb(243, 244, 246));
    private static readonly Brush Dark = Frozen(Color.FromRgb(48, 49, 56));

    private readonly TextBlock _selection = new() { FontSize = 11, Foreground = Good, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8) };
    private readonly TextBlock _summary = new() { FontSize = 12, Foreground = Frozen(Color.FromRgb(130, 133, 141)), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 6) };
    private readonly TextBlock _counter = new() { FontSize = 10, FontWeight = FontWeights.Medium, Foreground = Frozen(Color.FromRgb(112, 101, 129)), Margin = new Thickness(0, 0, 0, 6) };
    private readonly TextBlock _text = new() { FontSize = 16, TextWrapping = TextWrapping.Wrap, Foreground = Ink, LineHeight = 23 };
    private readonly TextBlock _status = new() { FontSize = 12, FontWeight = FontWeights.Medium, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 0) };
    private readonly WrapPanel _buttons = new() { Margin = new Thickness(0, 10, 0, 0) };
    private readonly Button _back = IconButton("←", "Previous step");
    private readonly Button _close = IconButton("×", "Hide Pip’s reply");
    private readonly DispatcherTimer _reveal = new() { Interval = TimeSpan.FromMilliseconds(140) };
    private readonly DispatcherTimer _advance = new();
    private readonly List<SolidColorBrush> _words = [];
    private IReadOnlyList<string> _steps = [];
    private List<Page> _pages = [];
    private IReadOnlyList<string> _areas = [], _areasAtStepStart = [];
    private int _index, _word;
    private bool _ticked, _reducedMotion;

    /// <summary>The learner asked for help with a step ("I'm stuck") or for more ("Explain more").</summary>
    internal Action<string>? Ask { get; set; }
    /// <summary>Moving to another page clears the screen highlight of the previous one.</summary>
    internal Action? PageChanged { get; set; }
    /// <summary>The shown page is about the reply (-1) or a step (its index), so Pip can go to that place on screen.</summary>
    internal Action<int>? Focus { get; set; }
    /// <summary>A ticked step: Pip waves.</summary>
    internal Action? Celebrate { get; set; }
    internal Action? AskSomethingElse { get; set; }
    internal bool IsShowing => _pages.Count > 0;
    internal string? CurrentPhrase => _pages.Count > _index ? Phrase : null;
    internal bool ReducedMotion { get => _reducedMotion; set { _reducedMotion = value; if (value) FinishReveal(); } }

    internal ReplyBubbleWindow()
    {
        Title = "Pip’s reply";
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        Topmost = true; ShowInTaskbar = false; ShowActivated = false; ResizeMode = ResizeMode.NoResize;
        Width = 360; SizeToContent = SizeToContent.Height;
        var header = new DockPanel();
        var corner = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(8, -8, -8, 0) };
        corner.Children.Add(_back); corner.Children.Add(_close);
        DockPanel.SetDock(corner, Dock.Right);
        header.Children.Add(corner);
        var titles = new StackPanel();
        titles.Children.Add(_selection); titles.Children.Add(_summary); titles.Children.Add(_counter);
        header.Children.Add(titles);
        var stack = new StackPanel();
        stack.Children.Add(header); stack.Children.Add(_text); stack.Children.Add(_status);
        stack.Children.Add(_buttons);
        Content = new Border
        {
            Child = stack, Padding = new Thickness(18, 16, 18, 16), CornerRadius = new CornerRadius(22), Margin = new Thickness(10),
            Background = Frozen(Color.FromRgb(254, 254, 255)), BorderBrush = Frozen(Color.FromRgb(226, 227, 233)), BorderThickness = new Thickness(1),
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 24, ShadowDepth = 6, Color = Color.FromRgb(32, 33, 44), Opacity = 0.14 },
        };
        AutomationProperties.SetLiveSetting(_text, AutomationLiveSetting.Polite);
        _back.Click += (_, _) => GoTo(_index - 1);
        _close.Click += (_, _) => Dismiss();
        _text.MouseLeftButtonDown += (_, _) => { if (_reveal.IsEnabled) FinishReveal(); };
        _reveal.Tick += (_, _) => RevealWord();
        _advance.Tick += (_, _) => { _advance.Stop(); GoTo(_index + 1); };
        SourceInitialized += (_, _) =>
        {
            // WS_EX_NOACTIVATE: clicking Done or a choice never takes the keyboard from Excel.
            var handle = new WindowInteropHelper(this).Handle;
            SetWindowLongPtr(handle, -20, new IntPtr(GetWindowLongPtr(handle, -20).ToInt64() | 0x08000000L));
        };
        Closed += (_, _) => { _reveal.Stop(); _advance.Stop(); };
    }

    // ---- Content ----

    /// <summary>A short line from Pip with no lesson: a greeting, "Thinking…" or a problem.</summary>
    internal void Say(string line)
    {
        _steps = [];
        _summary.Text = ""; _summary.Visibility = Visibility.Collapsed;
        _pages = [new Page(PageKind.Text, line, Last: true)];
        GoTo(0, buttons: false);
        if (!IsVisible) Show();
    }

    internal void ShowReply(string reply, IReadOnlyList<string>? steps = null)
    {
        _steps = steps ?? [];
        // A lesson starts straight at step 1, with what it achieves above the steps.
        _summary.Text = _steps.Count == 0 ? "" : WithoutEmoji(TeachingReply.Clean(reply));
        _summary.Visibility = _summary.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        if (_steps.Count == 0)
        {
            var paragraphs = TeachingReply.Clean(reply).Split("\n\n", StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (paragraphs.Length == 0) paragraphs = [TeachingReply.Clean(reply)];
            _pages = paragraphs.Select((text, i) => new Page(PageKind.Text, text, Last: i == paragraphs.Length - 1)).ToList();
        }
        else
        {
            _pages = [.. _steps.Select((_, i) => new Page(PageKind.Step, Step: i))];
            _pages.Add(new Page(PageKind.Finished));
        }
        GoTo(0);
        if (!IsVisible) Show();
    }

    internal void Resume() { if (IsShowing && !IsVisible) Show(); }

    internal void Dismiss()
    {
        _reveal.Stop(); _advance.Stop();
        _pages = []; _steps = []; _index = 0;
        _text.Inlines.Clear();
        Hide();
    }

    /// <summary>Excel's live selection: shown on the card, and used to tick selection steps the learner has really done.</summary>
    internal void UpdateSelection(ExcelContext? context, string line)
    {
        _selection.Text = line; _selection.ToolTip = line;
        _selection.Visibility = line.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        _areas = context?.Areas ?? [];
        CheckStep();
    }

    private void CheckStep()
    {
        if (_index >= _pages.Count || _pages[_index] is not { Kind: PageKind.Step } page || _ticked || _areas.Count == 0 ||
            _areas.SequenceEqual(_areasAtStepStart)) return;
        var (state, missing) = StepCheck.Check(_steps[page.Step], _steps.Take(page.Step).ToArray(), _areas);
        if (state == StepState.Done)
        {
            _ticked = true;
            SetStatus($"That’s it! Excel shows {string.Join(", ", _areas)}.", true);
            Celebrate?.Invoke();
            _advance.Interval = TimeSpan.FromMilliseconds(_reducedMotion ? 600 : 1400);
            _advance.Start();
        }
        else if (state == StepState.Missing)
            SetStatus($"Not yet: {string.Join(", ", missing)} still {(missing.Count == 1 ? "needs" : "need")} selecting.", false);
    }

    // ---- Pages ----

    internal void GoTo(int page, bool buttons = true)
    {
        if (page < 0 || page >= _pages.Count) return;
        if (page != _index) PageChanged?.Invoke();
        _advance.Stop();
        _index = page; _ticked = false; _areasAtStepStart = _areas;
        _status.Text = ""; _status.Visibility = Visibility.Collapsed;
        BuildButtons(buttons);
        _counter.Text = _pages[page].Kind switch
        {
            PageKind.Step => $"STEP {_pages[page].Step + 1} OF {_steps.Count}",
            _ => "",
        };
        _counter.Visibility = _counter.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        _back.Visibility = _pages[page].Kind == PageKind.Step && page > 0 ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetName(_text, Phrase);
        UIElementAutomationPeer.FromElement(_text)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        StartReveal();
        if (buttons) FocusCurrent();
    }

    private void FocusCurrent()
    {
        if (_index >= _pages.Count) return;
        if (_pages[_index].Kind == PageKind.Step) Focus?.Invoke(_pages[_index].Step);
        else if (_pages[_index].Kind == PageKind.Text && _index == 0 && _steps.Count == 0) Focus?.Invoke(-1);
    }

    private string Phrase => WithoutEmoji(RawPhrase);

    /// <summary>Pip's card never shows emoji, even if a reply contains some.</summary>
    internal static string WithoutEmoji(string text)
    {
        var kept = new System.Text.StringBuilder(text.Length);
        foreach (var rune in text.EnumerateRunes())
        {
            var v = rune.Value;
            if (v >= 0x1F000 || v is >= 0x2600 and <= 0x27BF or >= 0x2B00 and <= 0x2BFF or 0xFE0F or 0x200D or >= 0x2190 and <= 0x21FF) continue;
            kept.Append(rune.ToString());
        }
        return kept.ToString().Replace("  ", " ").Trim();
    }

    private string RawPhrase => _index >= _pages.Count ? "" : _pages[_index] switch
    {
        { Kind: PageKind.Text } page => page.Text,
        { Kind: PageKind.Step } page => _steps[page.Step],
        _ => _steps.Count == 0 ? "" : "All done. You did every step.",
    };

    private void BuildButtons(bool show)
    {
        _buttons.Children.Clear();
        if (!show || _index >= _pages.Count) return;
        void Add(string title, bool primary, Action action)
        {
            var button = new Button
            {
                Content = title, FontSize = 12, Padding = new Thickness(13, 7, 13, 7), Margin = new Thickness(0, 0, 8, 6), MinHeight = 32,
                Background = primary ? Dark : Soft, Foreground = primary ? Brushes.White : Ink, FontWeight = primary ? FontWeights.SemiBold : FontWeights.Normal,
            };
            button.Click += (_, _) => action();
            _buttons.Children.Add(button);
        }
        var page = _pages[_index];
        switch (page.Kind)
        {
            case PageKind.Text when !page.Last:
                Add("Next →", true, () => GoTo(_index + 1));
                break;
            case PageKind.Text when page.Text != "Thinking…":
                Add("Got it", true, Dismiss);
                Add("Explain more", false, () => Ask?.Invoke("Explain that a little more, with an example."));
                break;
            case PageKind.Step:
                Add("Done", true, () => GoTo(_index + 1));
                Add("Show me again", false, Replay);
                Add("I’m stuck", false, () => Ask?.Invoke($"I'm stuck on step {page.Step + 1}: {_steps[page.Step]} What should I do from here?"));
                break;
            case PageKind.Finished:
                Add("Ask something else", true, () => { Dismiss(); AskSomethingElse?.Invoke(); });
                Add("Start again", false, () => GoTo(0));
                break;
        }
    }

    private void Replay()
    {
        PageChanged?.Invoke();
        FocusCurrent();
        _ticked = false; _areasAtStepStart = _areas;
        _status.Visibility = Visibility.Collapsed;
        StartReveal();
    }

    private void SetStatus(string line, bool good)
    {
        _status.Text = line;
        _status.Foreground = good ? Good : Warn;
        _status.Visibility = Visibility.Visible;
    }

    // ---- Word by word ----

    [GeneratedRegex(@"\s+|\S+")] private static partial Regex Pieces();

    private void StartReveal()
    {
        _reveal.Stop(); _text.Inlines.Clear(); _words.Clear(); _word = 0;
        foreach (Match match in Pieces().Matches(Phrase))
        {
            var brush = new SolidColorBrush(Color.FromRgb(36, 37, 41)) { Opacity = 0 };
            _text.Inlines.Add(new Run(match.Value) { Foreground = brush });
            if (string.IsNullOrWhiteSpace(match.Value)) brush.Opacity = 1; else _words.Add(brush);
        }
        SetButtonsVisible(false);
        if (_reducedMotion || _words.Count == 0) { FinishReveal(); return; }
        var shift = new TranslateTransform(); _text.RenderTransform = shift;
        shift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(7, 0, TimeSpan.FromMilliseconds(220)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        RevealWord(); _reveal.Start();
    }

    private void RevealWord()
    {
        if (_word >= _words.Count) { FinishReveal(); return; }
        _words[_word++].BeginAnimation(Brush.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(120)));
    }

    internal void FinishReveal()
    {
        _reveal.Stop();
        foreach (var brush in _words) { brush.BeginAnimation(Brush.OpacityProperty, null); brush.Opacity = 1; }
        _text.RenderTransform = Transform.Identity;
        SetButtonsVisible(true);
        CheckStep();
    }

    private void SetButtonsVisible(bool visible)
    {
        _buttons.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        if (visible && !_reducedMotion) _buttons.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(200)));
    }

    // ---- Placement ----

    internal void Follow(Rect pipPixels, Rect? target = null, Rect? input = null)
    {
        if (pipPixels.IsEmpty || !IsVisible) return;
        var scale = VisualTreeHelper.GetDpi(this).DpiScaleX;
        var work = NativeDesktop.WorkAreaAt(new Point(pipPixels.Left + pipPixels.Width / 2, pipPixels.Top + pipPixels.Height / 2));
        Width = Math.Min(380, work.Width / scale - 24);
        UpdateLayout();
        var w = Width * scale; var h = Math.Max(80, ActualHeight) * scale;
        // Beside Pip first, then above or below it, then the corners of the screen: the card must never cover the place
        // Pip is pointing at, then should stay off Pip and the input bar, and otherwise stay close to Pip.
        var p = pipPixels;
        var candidates = new[] { new Rect(p.Left - w, p.Top, w, h), new Rect(p.Right, p.Top, w, h),
            new Rect(p.Left - w, p.Bottom - h, w, h), new Rect(p.Right, p.Bottom - h, w, h),
            new Rect(p.Left + p.Width / 2 - w / 2, p.Top - h, w, h), new Rect(p.Left + p.Width / 2 - w / 2, p.Bottom, w, h),
            new Rect(work.Left, work.Top, w, h), new Rect(work.Right - w, work.Top, w, h),
            new Rect(work.Left, work.Bottom - h, w, h), new Rect(work.Right - w, work.Bottom - h, w, h) };
        double Cost(Rect r) => (target is { } t ? Area(Rect.Intersect(r, t)) * 100 : 0) +
            (Area(Rect.Intersect(r, p)) + (input is { } panel ? Area(Rect.Intersect(r, panel)) : 0)) * 4 +
            Math.Sqrt(Math.Pow(r.X + r.Width / 2 - (p.X + p.Width / 2), 2) + Math.Pow(r.Y + r.Height / 2 - (p.Y + p.Height / 2), 2));
        var chosen = candidates.Select(r => new Rect(Math.Clamp(r.X, work.Left, Math.Max(work.Left, work.Right - w)),
            Math.Clamp(r.Y, work.Top, Math.Max(work.Top, work.Bottom - h)), w, h)).OrderBy(Cost).First();
        var handle = new WindowInteropHelper(this).EnsureHandle();
        NativeDesktop.SetWindowPos(handle, new IntPtr(-1), (int)chosen.X, (int)chosen.Y, 0, 0, 0x0011);
    }

    private static double Area(Rect r) => r.IsEmpty ? 0 : r.Width * r.Height;

    private static Brush Frozen(Color color) { var brush = new SolidColorBrush(color); brush.Freeze(); return brush; }

    private static Button IconButton(string glyph, string name)
    {
        var button = new Button { Content = glyph, FontSize = 14, Width = 28, Height = 26, MinHeight = 26, Padding = new Thickness(0),
            Background = Brushes.Transparent, Foreground = Frozen(Color.FromRgb(150, 153, 162)), ToolTip = name };
        AutomationProperties.SetName(button, name);
        return button;
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);
}
