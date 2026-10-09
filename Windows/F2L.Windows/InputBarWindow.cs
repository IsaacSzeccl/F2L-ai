using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace F2L.Windows;

/// <summary>One rounded bar at the bottom centre of the screen: the question, the microphone and Send. Nothing else.
/// Mirrors the input bar in Sources/F2L/Companion.swift.</summary>
internal sealed class InputBarWindow : Window
{
    internal const string AskPlaceholder = "Ask Pip anything…";

    internal TextBox QuestionBox { get; } = new()
    {
        MinHeight = 22, MaxHeight = 92, TextWrapping = TextWrapping.Wrap, AcceptsReturn = true, FontSize = 14,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalAlignment = VerticalAlignment.Center,
    };
    internal Button SendButton { get; } = new()
    {
        Content = "↑", Width = 34, Height = 34, MinHeight = 34, FontSize = 19, Padding = new Thickness(0),
        Background = new SolidColorBrush(Color.FromRgb(48, 49, 56)), Foreground = Brushes.White, ToolTip = "Send · Enter",
    };
    internal Button MicButton { get; } = new()
    {
        Content = "◉", Width = 34, Height = 34, MinHeight = 34, FontSize = 15, Padding = new Thickness(0),
        Background = Brushes.Transparent, ToolTip = "Speak your question",
    };
    private readonly TextBlock _placeholder = new()
    {
        Text = AskPlaceholder, IsHitTestVisible = false, FontSize = 14, Foreground = new SolidColorBrush(Color.FromRgb(148, 151, 160)),
        VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(2, 0, 0, 0),
    };
    private bool _composing, _moved, _dodging;

    /// <summary>The learner dragged the bar somewhere else.</summary>
    internal event Action? Moved;

    /// <summary>Enter (not Shift+Enter, not IME confirmation, not a repeat) asks to send.</summary>
    internal event Action? SendRequested;

    internal InputBarWindow()
    {
        Title = "Ask Pip";
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        Topmost = true; ShowInTaskbar = false; ShowActivated = false; ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        AutomationProperties.SetName(QuestionBox, "Ask Pip");
        AutomationProperties.SetName(SendButton, "Send question");
        AutomationProperties.SetName(MicButton, "Speak your question");
        var text = new Grid { Margin = new Thickness(0, 0, 8, 0) };
        text.Children.Add(QuestionBox); text.Children.Add(_placeholder);
        var row = new DockPanel { LastChildFill = true };
        SendButton.Margin = new Thickness(6, 0, 0, 0);
        DockPanel.SetDock(SendButton, Dock.Right); DockPanel.SetDock(MicButton, Dock.Right);
        row.Children.Add(SendButton); row.Children.Add(MicButton); row.Children.Add(text);
        var bar = new Border
        {
            Child = row, ToolTip = "Drag to move", Padding = new Thickness(22, 12, 14, 12), CornerRadius = new CornerRadius(24), Margin = new Thickness(10),
            Background = new SolidColorBrush(Color.FromRgb(254, 254, 255)), BorderBrush = new SolidColorBrush(Color.FromRgb(226, 227, 233)),
            BorderThickness = new Thickness(1),
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 24, ShadowDepth = 6, Color = Color.FromRgb(32, 33, 44), Opacity = 0.16 },
        };
        Content = bar;
        // Dragging the bar's background moves it anywhere; the text box and buttons keep their own clicks.
        bar.MouseLeftButtonDown += (_, e) =>
        {
            if (e.OriginalSource is not Border) return;
            DragMove();
            _moved = true; _dodging = false;
            Moved?.Invoke();
        };
        QuestionBox.TextChanged += (_, _) => _placeholder.Visibility = QuestionBox.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        TextCompositionManager.AddPreviewTextInputStartHandler(QuestionBox, (_, args) => _composing = !string.IsNullOrEmpty(args.TextComposition.CompositionText));
        TextCompositionManager.AddPreviewTextInputUpdateHandler(QuestionBox, (_, args) => _composing = !string.IsNullOrEmpty(args.TextComposition.CompositionText));
        TextCompositionManager.AddPreviewTextInputHandler(QuestionBox, (_, _) => _composing = false);
        QuestionBox.LostKeyboardFocus += (_, _) => _composing = false;
        // Preview runs before an AcceptsReturn TextBox consumes Enter as a newline.
        QuestionBox.PreviewKeyDown += (_, e) =>
        {
            if (!ComposerKeys.ShouldSend(e.Key, Keyboard.Modifiers, _composing)) return;
            e.Handled = true;
            if (!e.IsRepeat) SendRequested?.Invoke();
        };
    }

    internal string Placeholder { get => _placeholder.Text; set => _placeholder.Text = value; }

    /// <summary>Centres the bar at the bottom of the work area (the top while it dodges a target), unless the learner
    /// moved it: then it stays there, growing upwards.</summary>
    internal void Place()
    {
        var work = SystemParameters.WorkArea;
        Width = Math.Min(640, work.Width - 12);
        var oldBottom = Top + ActualHeight;
        UpdateLayout();
        var height = ActualHeight > 0 ? ActualHeight : 72;
        if (_moved) { Top = Math.Clamp(oldBottom - height, work.Top, Math.Max(work.Top, work.Bottom - height)); return; }
        Left = work.Left + (work.Width - Width) / 2;
        Top = _dodging ? work.Top + 8 : work.Bottom - height - 8;
    }

    internal void Dodge(bool dodge)
    {
        if (_moved || _dodging == dodge) return;
        _dodging = dodge;
        Place();
    }

    internal bool IsMoved => _moved;
    internal void ResetPosition() { _moved = false; _dodging = false; Place(); }
}
