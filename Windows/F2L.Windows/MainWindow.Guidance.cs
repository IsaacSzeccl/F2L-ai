using System.Windows;

namespace F2L.Windows;

public partial class MainWindow
{
    private TeachingCompanionWindow? _teachingPip;
    private Rect? _lastTargetBounds;
    // Pip stays in its corner and only the circle shows the place; "Pip walks to what it’s teaching" in Settings turns walking on.
    private bool _followTargets;
    private bool _reducedMotion = !SystemParameters.ClientAreaAnimation;
    private QuestionIntent _questionIntent;

    private Rect PanelPixels()
    {
        if (!_panelOpen || !IsLoaded || !_input.IsVisible || PresentationSource.FromVisual(_input) is null) return Rect.Empty;
        _input.UpdateLayout();
        return new Rect(_input.PointToScreen(new Point()), _input.PointToScreen(new Point(_input.ActualWidth, _input.ActualHeight)));
    }

    internal bool IsPipFollowing => _teachingPip is not null;

    internal void UpdateTeachingCompanion(Rect target)
    {
        _lastTargetBounds = target;
        if (_targetCapture is { } capture && !NativeDesktop.IsSnapshotCurrent(capture)) { StopTeachingCompanion(); return; }
        if (!_followTargets || !_panelOpen || !IsLoaded || _isListening || _finishingDictation || IsRequestPending)
        { StopTeachingCompanion(); return; }
        var scale = (_targetCapture?.Dpi is > 0 ? _targetCapture.Dpi : 96) / 96d;
        var work = NativeDesktop.WorkAreaAt(new Point(target.Left + target.Width / 2, target.Top + target.Height / 2));
        var width = Math.Clamp(PipArtView.Width * 0.8, 90, 144) * scale;
        // Stand clear of the whole circle, not just the target inside it.
        var spot = CompanionPlacement.Choose(TargetSnap.Circle(target, 5 * scale), work, new Size(width, width * 340 / 320), PanelPixels(),
            NativeDesktop.CursorPosition, scale, _teachingPip?.ScreenBounds);
        if (spot is null) { StopTeachingCompanion(); return; }
        var home = new Rect(PipArtView.PointToScreen(new Point()), PipArtView.PointToScreen(new Point(PipArtView.ActualWidth, PipArtView.ActualHeight)));
        _teachingPip ??= new TeachingCompanionWindow();
        _teachingPip.Moved = PositionBubble;
        _teachingPip.ReducedMotion = _reducedMotion;
        _teachingPip.Pip.SetExpression(_questionIntent);
        _teachingPip.Follow(spot, target, scale, home, PanelPixels());
        CompanionPanel.Visibility = Visibility.Hidden;
    }

    private void StopTeachingCompanion()
    {
        _teachingPip?.Close(); _teachingPip = null;
        CompanionPanel.Visibility = Visibility.Visible;
        PositionBubble();
    }

    internal void SetFollowTargets(bool on)
    {
        _followTargets = on;
        if (_followTargets && _lastTargetBounds is { } target) UpdateTeachingCompanion(target);
        else StopTeachingCompanion();
    }

    private void SetReducedMotion(bool on)
    {
        _reducedMotion = on;
        _bubble.ReducedMotion = _reducedMotion;
        PipArtView.SetReducedMotion(_reducedMotion);
        if (_teachingPip is not null)
        {
            _teachingPip.ReducedMotion = _reducedMotion;
            _teachingPip.Pip.SetReducedMotion(_reducedMotion);
        }
    }
}
