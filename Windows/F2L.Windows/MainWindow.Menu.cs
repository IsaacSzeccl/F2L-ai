using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace F2L.Windows;

/// <summary>Pip's ··· menu, Settings and the learning and profile window. Mirrors Sources/F2L/CompanionMenu.swift.</summary>
public partial class MainWindow
{
    /// <summary>Pip's ··· menu, built each time it opens so it shows what is true now (which AI has a key, whether a
    /// highlight or a moved input bar can be put back). Preferences and keys live in Settings. Same as the Mac.</summary>
    private void More_Click(object sender, RoutedEventArgs e)
    {
        if (MoreButton.ContextMenu is not { } menu) return;
        menu.Items.Clear();
        MenuItem Item(string header, Action action, bool? check = null)
        {
            var item = new MenuItem { Header = header, IsCheckable = check is not null, IsChecked = check == true };
            item.Click += (_, _) => action();
            return item;
        }
        menu.Items.Add(Item("New chat", NewChat));
        menu.Items.Add(Item("My learning & profile…", ShowProfile));
        menu.Items.Add(new Separator());
        var current = CoachSettings.Current().Provider;
        var providers = new MenuItem { Header = $"AI: {current.Name()}" };
        foreach (var provider in Providers.All)
        {
            var ready = !string.IsNullOrWhiteSpace(CredentialStore.Read(provider.KeyVariable()));
            providers.Items.Add(Item($"{provider.Name()} · {(ready ? "Key added" : "No key yet · add it in Settings")}", () =>
            {
                CredentialStore.SetProvider(provider);
                if (!ready) ShowSettings();
            }, provider == current));
        }
        providers.Items.Add(new Separator());
        providers.Items.Add(Item("Add or change keys…", ShowSettings));
        menu.Items.Add(providers);
        menu.Items.Add(Item("Share my screen with Pip", () => SetScreenSharing(!_screenSharingEnabled), _screenSharingEnabled));
        var sizes = new MenuItem { Header = "Pip size" };
        foreach (var (title, width, height) in PipSizes)
            sizes.Items.Add(Item(title, () =>
            {
                if (_userPositioned) Top -= (height - PipArtView.Height) / 2;
                PipArtView.Width = width; PipArtView.Height = height;
                LayoutCompanion();
            }, PipArtView.Height == height));
        menu.Items.Add(sizes);
        menu.Items.Add(Item("Move Pip to the other side", () => { _leftAnchor = !_leftAnchor; _userPositioned = false; LayoutCompanion(); }));
        if (_guide is not null) menu.Items.Add(Item("Clear the highlight", ClearHighlight));
        if (_input.IsMoved) menu.Items.Add(Item("Put the input bar back", () => { _input.ResetPosition(); PositionBubble(); }));
        menu.Items.Add(Item("Hide the input bar", MinimiseConversation));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Settings…", ShowSettings));
        menu.Items.Add(Item("Quit F2L", Close));
        menu.PlacementTarget = MoreButton; menu.IsOpen = true;
    }

    internal void SetScreenSharing(bool on)
    {
        _screenSharingEnabled = on;
        if (!on) { ClearHighlight(); _selectionEnabled = false; _bubble.UpdateSelection(null, ""); }
    }

    private static readonly (string Title, double Width, double Height)[] PipSizes = [("Small", 112, 128), ("Medium", 144, 164), ("Large", 180, 205)];

    private void ShowSettings() => new SettingsWindow(new SettingsWindow.Hooks(
        () => _reducedMotion, SetReducedMotion, () => _followTargets, SetFollowTargets)) { Owner = _personalize is { IsVisible: true } ? _personalize : this }.ShowDialog();

    private void ShowProfile()
    {
        if (_personalize is { IsVisible: true }) { _personalize.Activate(); return; }
        _panelOpen = false; _input.Hide(); _bubble.Hide();
        _personalize = new PersonalizeWindow(_profileStore, _coach) { Owner = this };
        _personalize.Done = () => { if (!_closed) { _profileDocument = null; OpenConversation(); Greet(); } };
        // What they want to learn is saved as they change it, so the next answer already knows.
        _personalize.Changed = () => { if (!_closed) _profileDocument = null; };
        _personalize.OpenSettings = ShowSettings;
        _personalize.Show();
    }
}
