using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace F2L.Windows;

/// <summary>Circling places on screen: where a reply or lesson step happens (Excel cells, controls found by name through
/// UI Automation, words read on screen, a zoomed second look by the AI), and keeping the circle on the place while the
/// window moves. Mirrors Sources/F2L/CompanionPointing.swift.</summary>
public partial class MainWindow
{
    /// <summary>Sends Pip to where the reply or step happens and circles it, found on the screen as it is now: the
    /// window is pictured again and its words are read on this PC (Windows OCR), so a button or tab is circled where its
    /// name appears and an Excel cell where its column letter and row number meet. Excel's own confirmation and UI
    /// Automation's named controls are used too. The model's rough position is shown dashed at once and replaced by a
    /// checked place when one is found. Every decision goes to pointing.log. Mirrors point(at:) in Sources/F2L/Companion.swift.</summary>
    private async void PointAt(ScreenTarget? target, bool checkRequest)
    {
        if (target is null || _replyCapture is not { } capture || !_screenSharingEnabled) return;
        var cell = target.Cell is { } address ? CellReference.Parse(address) : null;
        // A direct "circle A1" can't be quietly answered with B1.
        if (checkRequest && cell is not null && _requestedCells.Count == 1 && !CellReference.MatchesRequest(cell, _requestedCells)) return;
        // A later step can happen in another app (the browser, after "Open your browser"): look for it there, by name,
        // since the AI's position belongs to the earlier screenshot.
        var sameApp = true;
        if (cell is null && _capture.GetTarget() is { } now && now.Process != capture.SourceProcess)
        {
            try { var fresh = _capture.CaptureAppJpeg(now); Array.Clear(fresh.JpegBytes); capture = fresh; sameApp = false; }
            catch (ScreenCaptureException) { }
        }
        var version = _highlightVersion;
        Rect? estimate = sameApp && target.HasBox ? TargetGeometry.FromScreenshot(capture, target) : null;
        try
        {
            if (cell is not null)
            {
                var result = await _excel.ResolveAsync(capture, cell, _lifetime.Token);
                if (version != _highlightVersion || _closed) return;
                if (result is { Verified: true, Bounds: { } bounds })
                {
                    PointingLog.Record(target, "excel-verified", bounds);
                    ShowTarget(capture, bounds, true, cell, result.Sheet, persistent: true);
                    return;
                }
            }
            // Go straight to where the model saw it (dashed) while the screen is read; a checked place replaces it.
            if (estimate is { } quick) ShowTarget(capture, quick, false, null, null, persistent: true);
            // Picture the window as it is now and read it; the picture is kept only until this place is found.
            var (lines, picture) = await ReadScreenNowAsync(capture);
            using var forget = new PictureEraser(picture);
            if (version != _highlightVersion || _closed) return;
            Rect? place = null;
            string source;
            if (cell is not null)
            {
                var range = target.Label.Contains(':') && StepCheck.References("select " + target.Label).Count == 1 ? target.Label : cell.Address;
                place = ScreenText.ExcelCell(range, lines.SelectMany(line => line));
                source = place is null ? "cell headings not visible" : "screen-headings";
            }
            else
            {
                var controls = await TargetSnap.ControlsAsync(capture.SourceWindow, _lifetime.Token);
                if (version != _highlightVersion || _closed) return;
                place = TargetSnap.Snap(estimate, target.Label, controls, capture.Dpi / 96d);
                source = "ui-automation";
                if (place is null)
                {
                    place = TargetSnap.Snap(estimate, target.Label, ScreenText.Candidates(lines), capture.Dpi / 96d, byPosition: false);
                    source = place is null ? $"no matching control ({controls.Count} controls, {lines.Sum(line => line.Count)} words)" : "screen-text";
                }
                // A recipe step whose on-screen name is not there: the interface may have moved on, so say what the
                // recipe says to try instead of letting the learner follow a circle drawn around a guess.
                if (place is null && RecipeScreen.Hint(target.Label, _turnRecipes) is { } advice) _bubble.Advice(advice);
                // Not confirmed on screen (an icon with no visible name, or another app): a zoomed second look by the AI
                // around its first guess, or across the whole window when there is none. One short extra request.
                if (place is null && picture is { JpegBytes.Length: > 0 } shot && !TargetSnap.IsGeneric(target.Label) && _coach.IsConfigured && !_testing)
                {
                    var crop = ZoomLocate.Crop(estimate, shot.Bounds);
                    if (await Task.Run(() => ZoomLocate.CropJpeg(shot.JpegBytes, shot.Bounds, crop)) is { } piece
                        && await _coach.ZoomLocateAsync(target.Label, AppName(shot) ?? "this app", piece, crop, _lifetime.Token) is { } found)
                    {
                        if (version != _highlightVersion || _closed) return;
                        // Knowing where to look, a real control under the zoomed box makes it exact.
                        var snapped = TargetSnap.Snap(found, "", controls, capture.Dpi / 96d);
                        place = snapped ?? found;
                        source = snapped is null ? "model-zoom" : "zoom+ui-automation";
                    }
                }
            }
            PointingLog.Record(target, place is null && estimate is not null ? "model-estimate" : source, place ?? estimate, estimate);
            // Nothing on screen confirmed it (an icon without a visible name): the dashed estimate stays.
            if (place is { } located) ShowTarget(capture, located, !source.StartsWith("model"), null, null, persistent: true);
        }
        catch (OperationCanceledException) { }
    }

    /// <summary>A fresh picture of the taught window with F2L's own windows made invisible for a moment, read with
    /// Windows OCR. Only the words and their places are kept.</summary>
    private async Task<(IReadOnlyList<IReadOnlyList<ScreenWord>> Lines, CapturedScreen? Picture)> ReadScreenNowAsync(CapturedScreen capture)
    {
        var app = new ForegroundApp(capture.SourceWindow, capture.SourceProcess);
        var ours = new List<Window> { this, _input, _bubble };
        if (_guide is not null) ours.Add(_guide);
        if (_teachingPip is not null) ours.Add(_teachingPip);
        var opacity = ours.Select(window => window.Opacity).ToArray();
        try
        {
            foreach (var window in ours) window.Opacity = 0;
            await Task.Delay(80, _lifetime.Token);
            var fresh = _capture.CaptureAppJpeg(app);
            // The caller erases the picture once the place is found (PictureEraser).
            return (await ScreenText.ReadAsync(fresh), fresh);
        }
        catch (ScreenCaptureException) { return ([], null); }
        finally
        {
            for (var i = 0; i < ours.Count; i++) ours[i].Opacity = opacity[i];
        }
    }

    private void ForgetPlaces() { _replyCapture = null; _replyTarget = null; _stepTargets = []; _requestedCells = []; }

    private void ShowTarget(CapturedScreen capture, Rect bounds, bool verified, CellReference? cell, string? sheet, bool persistent = false)
    {
        if (!TargetGeometry.IsUsable(bounds) || !NativeDesktop.IsSnapshotCurrent(capture) ||
            !NativeDesktop.PointBelongsToWindow(capture.SourceWindow, new Point(bounds.Left + bounds.Width / 2, bounds.Top + bounds.Height / 2)))
            return;
        _targetPersistent = persistent;
        _targetCapture = capture;
        _targetCell = cell; _targetSheet = sheet; _targetShown = DateTime.UtcNow;
        _guide ??= new GuideOverlayWindow();
        _guide.ShowTarget(bounds, verified);
        if (!_clickTimer.IsEnabled) { _clickWatch = new(); _clickTimer.Start(); }
        // The input bar never sits on the place Pip is pointing at (unless the learner put it there).
        var panel = PanelPixels();
        if (!panel.IsEmpty && panel.IntersectsWith(Rect.Inflate(TargetSnap.Circle(bounds), 16, 16))) _input.Dodge(true);
        UpdateTeachingCompanion(bounds);
        PositionBubble();
    }

    private async void WatchTarget(object? sender, EventArgs e)
    {
        if (_targetCapture is not { } capture || _checkingHighlight) return;
        if (_targetCell is null)
        {
            // A lesson step keeps its hint while it is shown; other approximate hints expire after 20 seconds.
            if (!NativeDesktop.IsSnapshotCurrent(capture) || (!_targetPersistent && DateTime.UtcNow - _targetShown > TimeSpan.FromSeconds(20))) ClearHighlight();
            return;
        }
        if (NativeDesktop.RefreshGeometry(capture) is not { } current) { ClearHighlight(); return; }
        capture = current;
        var cell = _targetCell;
        _checkingHighlight = true;
        var version = _highlightVersion;
        try
        {
            var result = await _excel.ResolveAsync(capture, cell, _lifetime.Token);
            if (version != _highlightVersion || _closed) return;
            if (NativeDesktop.IsSnapshotCurrent(capture) && result.Verified && result.Sheet == _targetSheet && result.Bounds is { } bounds)
            {
                _targetCapture = capture;
                _guide?.ShowTarget(bounds, true);
                UpdateTeachingCompanion(bounds);
            }
            else ClearHighlight();
        }
        catch (OperationCanceledException) { }
        finally { _checkingHighlight = false; }
    }

    private void ClearHighlight()
    {
        _highlightVersion++;
        _guide?.Close(); _guide = null;
        StopTeachingCompanion(); _lastTargetBounds = null;
        _targetCapture = null; _targetCell = null; _targetSheet = null;
        _input.Dodge(false);
    }
}

/// <summary>Erases a window picture's bytes when the place it was taken for has been found (or given up on).</summary>
internal readonly struct PictureEraser(CapturedScreen? picture) : IDisposable
{
    public void Dispose() { if (picture is not null) Array.Clear(picture.JpegBytes); }
}
