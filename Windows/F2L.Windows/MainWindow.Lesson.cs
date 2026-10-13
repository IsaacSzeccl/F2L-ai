using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace F2L.Windows;

/// <summary>How a lesson moves on by itself: a click on the circled place (with any keys the step says to hold), typing
/// into the focused box, or the app or website a step asks for coming to the front. Done stays for everything else.
/// Mirrors Sources/F2L/CompanionLesson.swift.</summary>
public partial class MainWindow
{
    /// <summary>20 times a second while Pip's card is up: a press on the circled place (with any keys the step says to
    /// hold) finishes a click step; twice a second during a typing step, whether the focused box got new text.</summary>
    private async void PollLesson()
    {
        if (!_bubble.IsVisible || _closed) { _clickTimer.Stop(); return; }
        var own = IsMouseOver || _input.IsMouseOver || _bubble.IsMouseOver;
        if (_clickWatch.Pressed(NativeDesktop.LeftButtonDown, NativeDesktop.CursorPosition, _lastTargetBounds, own)) _bubble.ClickedTarget(NativeDesktop.HeldKeys);
        if (++_lessonTicks % 10 == 0) CheckGoal();
        if (_lessonTicks % 10 != 0 || _readingTyping || _bubble.CurrentStep is not { } step || !ClickWatch.IsTypingStep(step)) return;
        _readingTyping = true;
        try
        {
            var value = await Task.Run(FocusedTextFingerprint);
            if (_bubble.CurrentStep == step && _typingWatch.Observe(value, DateTime.UtcNow)) _bubble.StepDone();
        }
        finally { _readingTyping = false; }
    }

    /// <summary>The length and a hash of the text in the focused box of the app in front (UI Automation), so a typing
    /// step can tick without F2L keeping what was typed. Null when no text box has focus.</summary>
    private static TypingWatch.Fingerprint? FocusedTextFingerprint()
    {
        try
        {
            // Typing into Pip's own question box is not the step.
            if (System.Windows.Automation.AutomationElement.FocusedElement is not { } element || element.Current.ProcessId == Environment.ProcessId ||
                !element.TryGetCurrentPattern(System.Windows.Automation.ValuePattern.Pattern, out var pattern)) return null;
            var text = ((System.Windows.Automation.ValuePattern)pattern).Current.Value ?? "";
            return new(text.Length, text.GetHashCode());
        }
        catch (Exception error) when (error is System.Windows.Automation.ElementNotAvailableException or InvalidOperationException or System.Runtime.InteropServices.COMException) { return null; }
    }

    /// <summary>"Open your browser", "Go to chatgpt.com": done when that app or page is in front, checked twice a second
    /// from the app's name and its window title. Pip's own windows in front don't count either way.</summary>
    private void CheckGoal()
    {
        if (_bubble.CurrentStep is not { } step || StepGoal.Of(step, AIToolLibrary.Shared) is not { } goal) return;
        // While Pip itself is in front (the learner just typed a question), the app they were using counts.
        if ((NativeDesktop.FrontApp() ?? (_capture.GetTarget() is { } last ? NativeDesktop.AppAndTitle(last.Window) : null)) is not { } front) return;
        var met = goal.IsMet(front.App, front.Title);
        if (_goalAtStart is not { } atStart)
        {
            _goalAtStart = met;
            if (met) _bubble.Note("You’re already there. Press Done to go on.");
            return;
        }
        if (met && !atStart) _bubble.StepDone();
    }

    /// <summary>Each page starts fresh: clicks on its circle and typing in its box are watched while it is shown.</summary>
    private void WatchLesson()
    {
        _clickWatch = new(); _typingWatch = new(); _goalAtStart = null;
        if (!_clickTimer.IsEnabled) _clickTimer.Start();
    }
}
