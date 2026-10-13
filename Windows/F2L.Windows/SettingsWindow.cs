using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;

namespace F2L.Windows;

/// <summary>Real settings, in the same round style as the welcome window: which AI Pip uses and its key, and how Pip
/// moves. Mirrors Sources/F2L/SettingsWindow.swift (the Mac one also shows macOS permissions).</summary>
internal sealed class SettingsWindow : Window
{
    /// <summary>What Settings changes in Pip, supplied by MainWindow.</summary>
    internal sealed record Hooks(Func<bool> ReducedMotion, Action<bool> SetReducedMotion, Func<bool> FollowTargets, Action<bool> SetFollowTargets);

    private static readonly Brush Cream = PersonalizeWindow.Brush("#FAF8F3"), Sage = PersonalizeWindow.Brush("#E8EEE5"),
        Green = PersonalizeWindow.Brush("#345D50"), Muted = PersonalizeWindow.Brush("#69736D"), Ink = PersonalizeWindow.Brush("#242529"),
        Line = PersonalizeWindow.Brush("#E0E5DE"), Ready = PersonalizeWindow.Brush("#378D74");
    private readonly Hooks _hooks;
    /// <summary>The provider whose key box is shown; starts as the one in use.</summary>
    private Provider _selected = CoachSettings.Current().Provider;
    private string _notice = "";
    private ScrollViewer? _scroll;

    internal SettingsWindow(Hooks hooks)
    {
        _hooks = hooks;
        Title = "F2L Settings";
        Width = 540; Height = Math.Min(760, SystemParameters.WorkArea.Height - 48);
        WindowStartupLocation = WindowStartupLocation.CenterOwner; ResizeMode = ResizeMode.NoResize;
        Background = Cream; Foreground = Ink;
        FontFamily = Application.Current.TryFindResource("UiFont") as FontFamily ?? new FontFamily("Segoe UI");
        Render();
    }

    private static TextBlock Text(string text, double size = 13, Brush? color = null, bool strong = false, double bottom = 12) =>
        new() { Text = text, FontSize = size, Foreground = color ?? Ink, FontWeight = strong ? FontWeights.SemiBold : FontWeights.Normal,
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, bottom), VerticalAlignment = VerticalAlignment.Center };

    private static Button Pill(string text, Action action, bool selected = false)
    {
        var button = new Button { Content = text, Background = selected ? Green : Sage, Foreground = selected ? Brushes.White : Green,
            Padding = new Thickness(18, 8, 18, 8), BorderThickness = new Thickness(0), FontSize = 12, MinHeight = 34,
            FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal, Cursor = System.Windows.Input.Cursors.Hand,
            Template = PersonalizeWindow.RoundTemplate(17), VerticalAlignment = VerticalAlignment.Center };
        AutomationProperties.SetName(button, text);
        button.Click += (_, _) => action();
        return button;
    }

    private static Border Card(UIElement child, bool highlighted = false) => new()
    {
        Child = child, Background = highlighted ? PersonalizeWindow.Brush("#F1F6EF") : Brushes.White, BorderBrush = highlighted ? Green : Line,
        BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(25), Padding = new Thickness(18, 8, 10, 8), Margin = new Thickness(0, 0, 0, 8),
    };

    private void Render()
    {
        var offset = _scroll?.VerticalOffset ?? 0;
        var root = new Grid { Margin = new Thickness(32, 24, 32, 20) };
        root.RowDefinitions.Add(new() { Height = GridLength.Auto });
        root.RowDefinitions.Add(new() { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new() { Height = GridLength.Auto });
        var header = new DockPanel { Margin = new Thickness(0, 0, 0, 16) };
        var art = new Image { Source = BrandArtwork.Image("Illustrations/settings-compass.png"), Width = 60, Height = 60, IsHitTestVisible = false };
        DockPanel.SetDock(art, Dock.Right); header.Children.Add(art);
        header.Children.Add(Text("Settings", 26, strong: true, bottom: 0)); root.Children.Add(header);
        var body = new StackPanel { Margin = new Thickness(0, 0, 12, 0) };
        _scroll = new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        _scroll.Loaded += (_, _) => _scroll.ScrollToVerticalOffset(offset);
        Grid.SetRow(_scroll, 1); root.Children.Add(_scroll);
        ProviderSection(body);
        PipSection(body);
        PrivacySection(body);
        var done = Pill("Done", Close, true); done.IsCancel = true; done.HorizontalAlignment = HorizontalAlignment.Right; done.Margin = new Thickness(0, 14, 0, 0);
        Grid.SetRow(done, 2); root.Children.Add(done);
        Content = root;
    }

    private static void Heading(StackPanel body, string text, double top = 0)
    {
        var heading = Text(text.ToUpperInvariant(), 11, Green, true); heading.Margin = new Thickness(4, top, 0, 12); body.Children.Add(heading);
    }

    // ---- Your AI ----

    private void ProviderSection(StackPanel body)
    {
        Heading(body, "Your AI");
        body.Children.Add(Text("Pip uses one AI at a time. Pick one, then paste its key. Keys stay in a private file on this computer; Git ignores it and never uploads it.", 12, Muted, bottom: 14));
        var current = CoachSettings.Current().Provider;
        foreach (var provider in Providers.All)
        {
            var ready = HasKey(provider);
            var row = new DockPanel();
            if (provider == current) { var inUse = Text("In use", 12, Green, true, 0); inUse.Margin = new Thickness(0, 0, 8, 0); DockPanel.SetDock(inUse, Dock.Right); row.Children.Add(inUse); }
            else
            {
                var use = Pill("Use", () =>
                {
                    CredentialStore.SetProvider(provider); _selected = provider;
                    _notice = ready ? $"Pip now uses {provider.Name()}." : $"Pip now uses {provider.Name()}. Paste its key below to start.";
                    Render();
                });
                DockPanel.SetDock(use, Dock.Right); row.Children.Add(use);
            }
            var dot = new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(9), Margin = new Thickness(0, 0, 12, 0),
                Background = provider == current ? Green : Brushes.White, BorderBrush = PersonalizeWindow.Brush("#CFD8CC"), BorderThickness = new Thickness(provider == current ? 0 : 1),
                Child = provider == current ? new Border { Width = 7, Height = 7, CornerRadius = new CornerRadius(3.5), Background = Brushes.White } : null };
            row.Children.Add(dot);
            var name = Text(provider.Name(), 14, strong: true, bottom: 0); name.Width = 120; row.Children.Add(name);
            row.Children.Add(Text(ready ? "Key added" : "No key yet", 12, ready ? Ready : Muted, bottom: 0));
            // The whole row picks which key box shows; its Use button (which handles its own click) switches the AI.
            var card = Card(row, provider == _selected);
            card.Cursor = System.Windows.Input.Cursors.Hand;
            AutomationProperties.SetName(card, $"{provider.Name()}, {(ready ? "key added" : "no key yet")}");
            card.MouseLeftButtonUp += (_, _) => { _selected = provider; _notice = ""; Render(); };
            body.Children.Add(card);
        }
        var selectedReady = HasKey(_selected);
        var label = Text(selectedReady ? $"Replace your {_selected.Name()} key" : $"Paste your {_selected.Name()} key", 13, strong: true, bottom: 8);
        label.Margin = new Thickness(4, 10, 0, 8); body.Children.Add(label);
        var key = new PasswordBox { FontSize = 14, Background = Brushes.Transparent, BorderThickness = new Thickness(0), VerticalContentAlignment = VerticalAlignment.Center };
        AutomationProperties.SetName(key, $"{_selected.Name()} API key");
        var hint = Text(selectedReady ? "Saved. Paste a new key to replace it" : $"Your {_selected.Name()} API key", 14, PersonalizeWindow.Brush("#A3ABA5"), bottom: 0);
        hint.IsHitTestVisible = false;
        key.PasswordChanged += (_, _) => hint.Visibility = key.Password.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        void SaveKey()
        {
            var value = key.Password.Trim(); key.Clear();
            if (value.Length == 0) _notice = "Paste a key first.";
            else if (CredentialStore.SetKey(_selected, value)) { CredentialStore.SetProvider(_selected); _notice = $"Saved. Pip now uses {_selected.Name()}."; }
            else _notice = "The key couldn’t be saved. Check that this computer’s F2L folder is writable, then try again.";
            Render();
        }
        key.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) { e.Handled = true; SaveKey(); } };
        var row2 = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
        var save = Pill("Save key", SaveKey, true); save.Margin = new Thickness(10, 0, 0, 0); DockPanel.SetDock(save, Dock.Right); row2.Children.Add(save);
        var layer = new Grid(); layer.Children.Add(hint); layer.Children.Add(key);
        row2.Children.Add(new Border { Child = layer, Background = Brushes.White, BorderBrush = Line, BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(22), Height = 44, Padding = new Thickness(18, 0, 18, 0) });
        body.Children.Add(row2);
        if (selectedReady)
        {
            var remove = Pill("Remove this key", () =>
            {
                _notice = CredentialStore.SetKey(_selected, "") ? $"{_selected.Name()}’s key was removed from this computer." : "The key couldn’t be removed. Please try again.";
                Render();
            });
            remove.Background = Brushes.Transparent; remove.HorizontalAlignment = HorizontalAlignment.Left; body.Children.Add(remove);
        }
        if (_notice.Length > 0) body.Children.Add(Text(_notice, 12, Green));
    }

    private static bool HasKey(Provider provider) => !string.IsNullOrWhiteSpace(CredentialStore.Read(provider.KeyVariable()));

    // ---- Pip ----

    private void PipSection(StackPanel body)
    {
        Heading(body, "Pip", 22);
        foreach (var (title, detail, on, set) in new (string, string, bool, Action<bool>)[]
        {
            ("Reduce animation", "Words appear at once and Pip moves less.", _hooks.ReducedMotion(), _hooks.SetReducedMotion),
            ("Pip walks to what it’s teaching", "Off: Pip stays in its corner and circles the place instead.", _hooks.FollowTargets(), _hooks.SetFollowTargets),
        })
        {
            var toggle = new CheckBox { IsChecked = on, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 4, 0) };
            AutomationProperties.SetName(toggle, title);
            toggle.Checked += (_, _) => set(true); toggle.Unchecked += (_, _) => set(false);
            var row = new DockPanel(); DockPanel.SetDock(toggle, Dock.Right); row.Children.Add(toggle);
            var copy = new StackPanel(); copy.Children.Add(Text(title, 14, strong: true, bottom: 2)); copy.Children.Add(Text(detail, 11, Muted, bottom: 0));
            row.Children.Add(copy);
            body.Children.Add(Card(row));
        }
    }

    // ---- Privacy ----

    private static void PrivacySection(StackPanel body)
    {
        Heading(body, "Privacy", 22);
        body.Children.Add(Text("The latest 500 messages, your draft and your profile are saved on this computer. Screenshots aren’t saved. Simple cell-pointing requests are checked locally with desktop Excel; other questions and a picture of the app you ask about go to the AI you chose.", 11, Muted));
        var show = Pill("Show the settings file", () =>
        {
            var path = CredentialStore.PrepareSettingsFile();
            if (File.Exists(path)) Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
            else Process.Start(new ProcessStartInfo("explorer.exe", $"\"{Path.GetDirectoryName(path)}\"") { UseShellExecute = true });
        });
        show.HorizontalAlignment = HorizontalAlignment.Left; body.Children.Add(show);
    }
}
