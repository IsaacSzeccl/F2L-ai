using System.Diagnostics;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace F2L.Windows;

/// <summary>The optional welcome: Your work / Your AI / Your plan. Round like Pip: pill fields and buttons, round
/// cards, numbered circles. Mirrors PersonalizeWindow.swift.</summary>
internal sealed class PersonalizeWindow : Window
{
    private static readonly Brush Cream = Brush("#FAF8F3"), Sage = Brush("#E8EEE5"), Green = Brush("#345D50"), Muted = Brush("#69736D"), Ink = Brush("#242529");
    private readonly ProfileStore _store;
    private readonly ICoachClient _coach;
    private ProfileDocument _original;
    private LearnerProfile _profile;
    private StarterPlan? _plan;
    private int _step;
    private int _renderedStep = -1;
    private ScrollViewer? _scroll;
    private bool _busy, _finished;
    private string _error = "";
    private CancellationTokenSource? _request;
    private Button? _primary;
    internal Action? Done;
    /// <summary>What they want to learn changed and was saved straight away (their profile already existed).</summary>
    internal Action? Changed;
    internal Action? OpenSettings;

    /// <summary>Set by MainWindow when F2L is quitting: closing then is not the learner skipping setup.</summary>
    internal bool AppClosing { get; set; }

    internal PersonalizeWindow(ProfileStore? store = null, ICoachClient? coach = null)
    {
        _store = store ?? new(); _coach = coach ?? new CoachClient(); _original = _store.Load();
        _profile = _original.Profile?.Normalized() ?? new(); _plan = _original.Plan;
        _step = _profile.IsReady && _plan is not null ? 2 : 0;
        Title = _original.Profile is null ? "Welcome to F2L" : "Your learning with Pip";
        Width = Math.Min(976, SystemParameters.WorkArea.Width - 48); Height = Math.Min(720, SystemParameters.WorkArea.Height - 48);
        WindowStartupLocation = WindowStartupLocation.CenterScreen; ResizeMode = ResizeMode.NoResize;
        Background = Cream; Foreground = Ink;
        FontFamily = Application.Current.TryFindResource("UiFont") as FontFamily ?? new FontFamily("Segoe UI");
        Closing += (_, e) =>
        {
            if (!_finished && !AppClosing)
            {
                try { _store.Save(_original with { OnboardingComplete = true }); }
                catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException)
                { _error = "Pip couldn’t save your choice. Please try again."; e.Cancel = true; Render(); return; }
            }
            _request?.Cancel(); _finished = true;
            if (!AppClosing) Done?.Invoke();
        };
        Render();
    }
    internal static Brush Brush(string color) => (Brush)new BrushConverter().ConvertFromString(color)!;
    private static TextBlock Text(string text, double size = 13, Brush? color = null, bool strong = false, double bottom = 12) =>
        new() { Text = text, FontSize = size, Foreground = color ?? Ink, FontWeight = strong ? FontWeights.SemiBold : FontWeights.Normal,
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, bottom), LineHeight = size * 1.45 };
    /// <summary>A button drawn as a pill (or a round card when <paramref name="radius"/> is given).</summary>
    internal static ControlTemplate RoundTemplate(double radius)
    {
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(radius));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.BorderBrushProperty, new System.Windows.Data.Binding("BorderBrush") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.BorderThicknessProperty, new System.Windows.Data.Binding("BorderThickness") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.PaddingProperty, new System.Windows.Data.Binding("Padding") { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(HorizontalAlignmentProperty, HorizontalAlignment.Center);
        presenter.SetValue(VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(presenter);
        return new ControlTemplate(typeof(Button)) { VisualTree = border };
    }
    private static Button ActionButton(string text, Action action, bool selected = false)
    {
        var button = new Button { Content = text, Background = selected ? Green : Sage, Foreground = selected ? Brushes.White : Green,
            Padding = new Thickness(22, 11, 22, 11), BorderThickness = new Thickness(0), FontSize = 13, MinHeight = 40,
            FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal,
            Margin = new Thickness(0, 0, 8, 8), Cursor = System.Windows.Input.Cursors.Hand, Template = RoundTemplate(20) };
        AutomationProperties.SetName(button, text);
        button.Click += (_, _) => action();
        return button;
    }
    /// <summary>A question with a pill-shaped text box under it.</summary>
    private void Field(StackPanel stack, string title, string value, string hint, Action<string> changed)
    {
        stack.Children.Add(Text(title, 13, Ink, true, 8));
        var box = new TextBox { Text = value, FontSize = 15, Padding = new Thickness(0), Background = Brushes.Transparent, Foreground = Ink,
            BorderThickness = new Thickness(0), VerticalContentAlignment = VerticalAlignment.Center };
        var hintText = new TextBlock { Text = hint, FontSize = 15, Foreground = Brush("#A3ABA5"), IsHitTestVisible = false, VerticalAlignment = VerticalAlignment.Center,
            Visibility = value.Length == 0 ? Visibility.Visible : Visibility.Collapsed };
        var layer = new Grid(); layer.Children.Add(hintText); layer.Children.Add(box);
        AutomationProperties.SetName(box, title);
        box.TextChanged += (_, _) =>
        {
            hintText.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            changed(box.Text); if (_primary is not null) _primary.IsEnabled = !_busy && (_step != 0 || _profile.IsReady);
        };
        stack.Children.Add(new Border { Child = layer, Background = Brushes.White, BorderBrush = Brush("#D8DFD5"), BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(24), Height = 48, Padding = new Thickness(22, 0, 22, 0), Margin = new Thickness(0, 0, 0, 22) });
    }
    private void Render()
    {
        var offset = _renderedStep == _step ? _scroll?.VerticalOffset ?? 0 : 0;
        _renderedStep = _step;
        var root = new Grid { Margin = new Thickness(18, 16, 18, 16) };
        root.ColumnDefinitions.Add(new() { Width = new GridLength(272) });
        root.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) });
        var sidebar = new Grid { Margin = new Thickness(24) };
        sidebar.RowDefinitions.Add(new() { Height = GridLength.Auto }); sidebar.RowDefinitions.Add(new() { Height = GridLength.Auto });
        sidebar.RowDefinitions.Add(new() { Height = new GridLength(1, GridUnitType.Star) }); sidebar.RowDefinitions.Add(new() { Height = GridLength.Auto });
        var brand = Text("F2L  ·  PIP", 10, Green, true, 32); sidebar.Children.Add(brand);
        var headline = Text(new[] { "Your work,\nyour way.", "Your pace.\nNo pressure.", "Small steps.\nReal progress." }[_step], 27, Green, true);
        Grid.SetRow(headline, 1); sidebar.Children.Add(headline);
        // Pip's illustration inside a big soft circle.
        var art = new Image { Source = new BitmapImage(new Uri("pack://application:,,,/F2L.Windows;component/Assets/Pip/welcome-journey.png")), Stretch = Stretch.Uniform, Margin = new Thickness(6) };
        AutomationProperties.SetName(art, "Pip, your learning companion");
        var halo = new Border { Width = 216, Height = 216, CornerRadius = new CornerRadius(108), Background = Brush("#F4F2EC"), Child = art,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetRow(halo, 2); sidebar.Children.Add(halo);
        var quote = Text("“One useful thing at a time.”", 14, Green, bottom: 0); Grid.SetRow(quote, 3); sidebar.Children.Add(quote);
        root.Children.Add(new Border { Background = Sage, CornerRadius = new CornerRadius(36), Child = sidebar });
        var right = new Grid { Margin = new Thickness(36, 10, 12, 0) }; Grid.SetColumn(right, 1); root.Children.Add(right);
        right.RowDefinitions.Add(new() { Height = GridLength.Auto }); right.RowDefinitions.Add(new() { Height = new GridLength(1, GridUnitType.Star) }); right.RowDefinitions.Add(new() { Height = GridLength.Auto });
        // Three numbered circles joined by a line.
        var progress = new System.Windows.Controls.Primitives.UniformGrid { Columns = 3, Margin = new Thickness(0, 0, 0, 24) };
        foreach (var (title, index) in new[] { "Your work", "Your AI", "Your plan" }.Select((text, index) => (text, index)))
        {
            bool done = index < _step, current = index == _step;
            var row = new Grid();
            row.ColumnDefinitions.Add(new() { Width = GridLength.Auto }); row.ColumnDefinitions.Add(new() { Width = new GridLength(1, GridUnitType.Star) });
            var dot = new Border { Width = 28, Height = 28, CornerRadius = new CornerRadius(14), Background = done || current ? Green : Brushes.White,
                BorderBrush = Brush("#CFD8CC"), BorderThickness = new Thickness(done || current ? 0 : 1),
                Child = new TextBlock { Text = done ? "✓" : $"{index + 1}", Foreground = done || current ? Brushes.White : Muted, FontWeight = FontWeights.SemiBold,
                    FontSize = 12, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
            row.Children.Add(dot);
            if (index < 2)
            {
                var line = new Border { Height = 3, CornerRadius = new CornerRadius(1.5), Background = done ? Green : Brush("#DEE3DC"), Margin = new Thickness(6, 0, 6, 0) };
                Grid.SetColumn(line, 1); row.Children.Add(line);
            }
            var segment = new StackPanel();
            segment.Children.Add(row);
            segment.Children.Add(Text(title, 11, current ? Green : Muted, current, 0));
            progress.Children.Add(segment);
        }
        right.Children.Add(progress);
        var content = new StackPanel { Margin = new Thickness(0, 0, 10, 12) };
        var scroll = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        _scroll = scroll;
        scroll.Loaded += (_, _) => scroll.ScrollToVerticalOffset(offset);
        content.IsEnabled = !_busy;
        Grid.SetRow(scroll, 1); right.Children.Add(scroll);
        if (_step == 0) World(content); else if (_step == 1) Pace(content); else Path(content);
        if (_error.Length > 0) content.Children.Add(Text(_error, 12, Brush("#944C32")));
        var footer = new StackPanel { Margin = new Thickness(0, 18, 0, 0) };
        var actions = new DockPanel();
        _primary = ActionButton(_step == 0 ? "Next" : _step == 1 ? (_busy ? "Making your plan…" : "Make my plan") : "Save & meet Pip", Next, true);
        _primary.IsEnabled = !_busy && (_step != 0 || _profile.IsReady); _primary.IsDefault = true;
        DockPanel.SetDock(_primary, Dock.Right); actions.Children.Add(_primary);
        if (_step == 1)
        {
            var local = ActionButton("Plan without AI", () => _ = MakePlan(false)); local.IsEnabled = !_busy;
            DockPanel.SetDock(local, Dock.Right); actions.Children.Add(local);
        }
        var back = ActionButton(_step == 0 ? (_original.Profile is null ? "Not now" : "Cancel") : _step == 2 ? "Edit my answers" : "Back", () =>
        {
            if (_step == 0) { Close(); return; }
            _step--; _error = ""; Render();
        });
        back.IsEnabled = !_busy; back.HorizontalAlignment = HorizontalAlignment.Left; actions.Children.Add(back); footer.Children.Add(actions);
        if (_original.Profile is not null)
        {
            var forget = ActionButton("Forget my profile", Forget); forget.Background = Brushes.Transparent; forget.FontSize = 10;
            forget.HorizontalAlignment = HorizontalAlignment.Left; footer.Children.Add(forget);
        }
        Grid.SetRow(footer, 2); right.Children.Add(footer); Content = root;
    }
    private void World(StackPanel body)
    {
        body.Children.Add(Text(_profile.Name.Length == 0 ? "Tell Pip about your work." : $"Tell Pip about your work, {_profile.Name}.", 26, strong: true, bottom: 10));
        body.Children.Add(Text("Pip uses this to fit every answer to your job. Type it your way; there are no wrong answers.", color: Muted, bottom: 26));
        Field(body, "What should Pip call you?", _profile.Name, "Your first name (optional)", value => _profile.Name = value);
        Field(body, "What do you do at work?", _profile.Role, "e.g. Operations coordinator at a logistics company", value => _profile.Role = value);
        Field(body, "What would you like help with at work?", _profile.Goal, "e.g. Weekly sales reports in Excel take me hours", value => _profile.Goal = value);
    }
    private void Pace(StackPanel body)
    {
        body.Children.Add(Text("How do you use AI today?", 26, strong: true, bottom: 10));
        body.Children.Add(Text("Pip changes how much it explains. Every starting point is fine.", color: Muted, bottom: 24));
        // Three round cards, each with Pip's emote in a circle.
        var cards = new System.Windows.Controls.Primitives.UniformGrid { Columns = 3, Margin = new Thickness(0, 0, 0, 26) };
        foreach (var option in LearnerProfile.Experiences)
        {
            var selected = _profile.Experience == option.Id;
            var inside = new StackPanel { Margin = new Thickness(12, 18, 12, 16) };
            inside.Children.Add(new Border { Width = 72, Height = 72, CornerRadius = new CornerRadius(36), Background = selected ? Sage : Cream, Margin = new Thickness(0, 0, 0, 12),
                Child = new Image { Margin = new Thickness(6), Source = PipEmotes.Image(option.Id == "new" ? PipEmote.Curious : option.Id == "some" ? PipEmote.Happy : PipEmote.Hello) } });
            inside.Children.Add(new TextBlock { Text = option.Title, FontSize = 14, FontWeight = FontWeights.SemiBold, Foreground = selected ? Green : Ink,
                TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 6) });
            inside.Children.Add(new TextBlock { Text = option.Detail, FontSize = 12, Foreground = Muted, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap });
            var card = new Button { Content = inside, Background = selected ? Brush("#F1F6EF") : Brushes.White, BorderBrush = selected ? Green : Brush("#E0E5DE"),
                BorderThickness = new Thickness(selected ? 1.5 : 1), Padding = new Thickness(0), Margin = new Thickness(0, 0, 12, 0),
                Cursor = System.Windows.Input.Cursors.Hand, Template = RoundTemplate(28), HorizontalContentAlignment = HorizontalAlignment.Stretch };
            AutomationProperties.SetName(card, option.Title);
            card.Click += (_, _) => { _profile.Experience = option.Id; Render(); };
            cards.Children.Add(card);
        }
        body.Children.Add(cards);
        body.Children.Add(Text("Tools you already use at work · optional", 13, Ink, true, 10));
        var tools = new System.Windows.Controls.Primitives.UniformGrid { Columns = 3 };
        foreach (var tool in ToolCatalog.All) tools.Children.Add(ActionButton(tool.Name, () =>
        {
            _profile.ExistingTools = _profile.ExistingTools.Contains(tool.Id) ? _profile.ExistingTools.Where(x => x != tool.Id).ToArray() : [.. _profile.ExistingTools, tool.Id]; Render();
        }, _profile.ExistingTools.Contains(tool.Id)));
        body.Children.Add(tools);
        var toggle = new CheckBox { Content = "Use this to personalise Pip’s help", IsChecked = _profile.PersonalizationEnabled, FontSize = 13, Margin = new Thickness(0, 14, 0, 10) };
        toggle.Checked += (_, _) => _profile.PersonalizationEnabled = true; toggle.Unchecked += (_, _) => _profile.PersonalizationEnabled = false; body.Children.Add(toggle);
        body.Children.Add(Text($"Saved only on this computer. Make my plan sends your role, work goal, AI level and tools (never your name or screen) to {_coach.ProviderName}. Plan without AI stays on this computer.", 11, Muted));
    }
    private void Path(StackPanel body)
    {
        var plan = _plan ?? StarterPlan.Draft(_profile);
        Learning(body, plan);
        body.Children.Add(Text(plan.Source == "local" ? "YOUR STARTER DRAFT · MADE ON THIS DEVICE" : "YOUR PERSONAL PLAN · WITH " + plan.Source.ToUpperInvariant(), 10, Green, true));
        var heading = new DockPanel();
        var cheer = new System.Windows.Controls.Image { Width = 56, Height = 56, Source = PipEmotes.Image(PipEmote.Cheer), VerticalAlignment = VerticalAlignment.Top };
        DockPanel.SetDock(cheer, Dock.Right);
        heading.Children.Add(cheer); heading.Children.Add(Text(plan.Title, 25, strong: true));
        body.Children.Add(heading); body.Children.Add(Text(plan.Summary, color: Muted, bottom: 22));
        body.Children.Add(Text("A SMALL TOOLKIT, CHOSEN FOR YOU", 11, Green, true));
        foreach (var suggestion in plan.Tools)
        {
            if (ToolCatalog.Find(suggestion.Id) is not { } tool) continue;
            var card = new DockPanel { Margin = new Thickness(16) };
            var explore = ActionButton("Explore", () => Process.Start(new ProcessStartInfo(tool.Url) { UseShellExecute = true }));
            explore.VerticalAlignment = VerticalAlignment.Center; DockPanel.SetDock(explore, Dock.Right); card.Children.Add(explore);
            var copy = new StackPanel { Margin = new Thickness(0, 0, 14, 0) }; copy.Children.Add(Text(tool.Name, 14, strong: true, bottom: 6)); copy.Children.Add(Text(suggestion.Reason, 12, Muted, bottom: 0)); card.Children.Add(copy);
            body.Children.Add(new Border { Background = Brushes.White, BorderBrush = Brush("#E0E5DE"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(26), Child = card, Margin = new Thickness(0, 0, 0, 10), Padding = new Thickness(8, 0, 4, 0) });
        }
        body.Children.Add(Text("Start with tools your workplace already approves. Features and access depend on your plan. These are suggestions, not connected accounts.", 11, Muted, bottom: 24));
        body.Children.Add(Text("A WORKFLOW TO TRY", 11, Green, true));
        foreach (var (item, index) in plan.Workflow.Select((item, index) => (item, index)))
        {
            body.Children.Add(Text($"0{index + 1}   {item.Title}", 14, Green, true, 6)); body.Children.Add(Text(item.Detail, 12, Muted, bottom: 20));
        }
        var actions = new WrapPanel();
        var refresh = ActionButton(_busy ? "Making your plan…" : "Refresh with AI", () => _ = MakePlan(true)); refresh.IsEnabled = !_busy; actions.Children.Add(refresh); body.Children.Add(actions);
        if (!_coach.IsConfigured) actions.Children.Add(ActionButton("Set up AI in Settings", () => OpenSettings?.Invoke()));
        body.Children.Add(actions);
        body.Children.Add(Text("You can come back here any time from My learning & profile in Pip’s ··· menu.", 11, Muted));
    }

    /// <summary>What they want to learn: Pip's ideas as round chips to tick, and a field for their own. Pip offers the
    /// ticked ones when it opens, and nothing starts until they pick one.</summary>
    private void Learning(StackPanel body, StarterPlan plan)
    {
        body.Children.Add(Text("What do you want to learn?", 25, strong: true, bottom: 8));
        body.Children.Add(Text($"Pick up to {LearnerProfile.MaxLearning}, or add your own. Pip offers these when it opens; nothing starts until you choose.", color: Muted, bottom: 18));
        var chips = new System.Windows.Controls.Primitives.UniformGrid { Columns = 2, Margin = new Thickness(0, 0, 0, 8) };
        foreach (var idea in LearnerProfile.LearningIdeas(_profile, plan))
        {
            var chosen = _profile.Learning.Contains(idea);
            var chip = ActionButton(idea, () => ToggleLearning(idea), chosen);
            chip.IsEnabled = chosen || _profile.Learning.Length < LearnerProfile.MaxLearning;
            chips.Children.Add(chip);
        }
        body.Children.Add(chips);
        var row = new DockPanel { Margin = new Thickness(0, 0, 0, 30) };
        var box = new TextBox { FontSize = 14, Padding = new Thickness(0), Background = Brushes.Transparent, Foreground = Ink,
            BorderThickness = new Thickness(0), VerticalContentAlignment = VerticalAlignment.Center };
        var hint = new TextBlock { Text = "Something else you want to learn", FontSize = 14, Foreground = Brush("#A3ABA5"), IsHitTestVisible = false, VerticalAlignment = VerticalAlignment.Center };
        box.TextChanged += (_, _) => hint.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        void Add() { if (box.Text.Trim().Length > 0) { _profile.Learning = [.. _profile.Learning, box.Text.Trim()]; LearningChanged(); } }
        box.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) { e.Handled = true; Add(); } };
        AutomationProperties.SetName(box, "Something else you want to learn");
        var add = ActionButton("Add", Add); add.Margin = new Thickness(10, 0, 0, 0);
        DockPanel.SetDock(add, Dock.Right); row.Children.Add(add);
        var layer = new Grid(); layer.Children.Add(hint); layer.Children.Add(box);
        row.Children.Add(new Border { Child = layer, Background = Brushes.White, BorderBrush = Brush("#D8DFD5"), BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(22), Height = 44, Padding = new Thickness(20, 0, 20, 0) });
        body.Children.Add(row);
    }

    private void ToggleLearning(string topic)
    {
        _profile.Learning = _profile.Learning.Contains(topic) ? _profile.Learning.Where(x => x != topic).ToArray() : [.. _profile.Learning, topic];
        LearningChanged();
    }

    /// <summary>Saved straight away once they have a profile, so Pip's next answer already knows.</summary>
    private void LearningChanged()
    {
        _profile = _profile.Normalized();
        if (_original.Profile is not null && !_busy)
        {
            var saved = new ProfileDocument { Profile = _profile, Plan = _plan ?? _original.Plan ?? StarterPlan.Draft(_profile), OnboardingComplete = true };
            try { _store.Save(saved); _original = saved; Changed?.Invoke(); }
            catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException)
            { _error = "Your choice couldn’t be saved. Check that this computer’s F2L folder is writable, then try again."; }
        }
        Render();
    }
    private void Next()
    {
        // The kind of help comes from what they typed, so there is nothing extra to pick.
        _profile.Focus = LearnerProfile.InferFocus(_profile.Role, _profile.Goal);
        _profile = _profile.Normalized();
        if (_step == 0) { if (!_profile.IsReady) return; _step = 1; _error = ""; Render(); }
        else if (_step == 1) _ = MakePlan(true);
        else Save();
    }
    private async Task MakePlan(bool useAI)
    {
        if (_busy) return;
        _profile.Focus = LearnerProfile.InferFocus(_profile.Role, _profile.Goal);
        _profile = _profile.Normalized(); _plan = StarterPlan.Draft(_profile); _error = "";
        if (!useAI || !_coach.IsConfigured)
        {
            if (useAI) _error = "Your AI isn’t connected yet, so Pip made a starter draft on this device. Save it now, or set up AI and refresh it.";
            _step = 2; Render(); return;
        }
        _busy = true; _request = new(); Render();
        try { var result = await _coach.StarterPlanAsync(_profile.Normalized(), _request.Token); if (_finished) return; _plan = result; }
        catch (OperationCanceledException) { if (_finished) return; _error = "The request was cancelled. Your starter draft is ready."; }
        catch (CoachRequestException error) { if (_finished) return; _error = error.Message; }
        catch (Exception) { if (_finished) return; _error = "The AI plan isn’t available right now. You can keep this starter draft and try again later."; }
        _busy = false; _step = 2; Render();
    }
    private void Save()
    {
        if (_busy) return;
        var plan = _plan ?? StarterPlan.Draft(_profile);
        try { _store.Save(new() { Profile = _profile, Plan = plan, OnboardingComplete = true }); _finished = true; Close(); }
        catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException) { _error = "Your profile couldn’t be saved. Check that this computer’s F2L folder is writable, then try again."; Render(); }
    }
    private void Forget()
    {
        if (MessageBox.Show(this, "Pip will stop adding this background to new questions. Earlier conversations and information already sent to an AI provider are not erased.",
            "Forget your profile and starter plan?", MessageBoxButton.OKCancel) != MessageBoxResult.OK) return;
        try { _store.Forget(); _finished = true; Close(); }
        catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException) { _error = "Your profile couldn’t be removed. Please try again."; Render(); }
    }
}
