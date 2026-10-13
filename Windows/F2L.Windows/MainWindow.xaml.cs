using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace F2L.Windows;

/// <summary>Resting Pip, the input bar at the bottom centre, Pip's reply card, screen sharing, Excel selection,
/// highlights and the teaching companion. Mirrors CompanionController in Sources/F2L/Companion.swift.
/// Pip is silent: replies are shown, not spoken. This file holds the state, layout, the input bar, a question's round
/// trip, dictation and saving; the rest is split by job: MainWindow.Pointing.cs (circling places),
/// MainWindow.Lesson.cs (steps that finish by themselves), MainWindow.Menu.cs (the ··· menu, Settings, profile) and
/// MainWindow.Guidance.cs (the walking Pip).</summary>
public partial class MainWindow : Window
{
    internal const string Greeting = "How can I help you?";
    internal const string SelectionUnavailable = "Selection unavailable · finish editing the cell or close Excel’s dialog.";

    private readonly ICoachClient _coach;
    private readonly ConversationSession _session;
    private ConversationStore _store;
    private readonly InputBarWindow _input = new();
    private readonly ReplyBubbleWindow _bubble = new();
    private readonly IScreenCaptureService _capture;
    private readonly ExcelTargetResolver _excel = new();
    private readonly PushToTalkInput _speechInput = new();
    private readonly DispatcherTimer _saveDraft = new() { Interval = TimeSpan.FromMilliseconds(600) };
    private readonly DispatcherTimer _watchTarget = new() { Interval = TimeSpan.FromMilliseconds(400) };
    /// <summary>While a place is circled, the mouse button is checked 20 times a second so clicking it moves the lesson on.</summary>
    private readonly DispatcherTimer _clickTimer = new() { Interval = TimeSpan.FromMilliseconds(50) };
    private ClickWatch _clickWatch = new();
    /// <summary>During a typing step, the focused box is checked twice a second (only its length and a hash, never the text).</summary>
    private TypingWatch _typingWatch = new();
    private int _lessonTicks;
    private bool _readingTyping;
    /// <summary>Whether the step's goal (an app or site in front) was already reached when the step appeared.</summary>
    private bool? _goalAtStart;
    private readonly DispatcherTimer _wave = new();
    private readonly CancellationTokenSource _lifetime = new();
    private readonly bool _testing;
    private CancellationTokenSource? _turnCancellation;
    private ConversationEntry? _pendingReply;
    private GuideOverlayWindow? _guide;
    private IntroWindow? _intro;
    private readonly ProfileStore _profileStore = new();
    private ProfileDocument? _profileDocument;
    /// <summary>Read once and again when the setup window closes, not on every question.</summary>
    private ProfileDocument Profile => _profileDocument ??= _testing ? new ProfileDocument() : _profileStore.Load();
    private PersonalizeWindow? _personalize;
    private CapturedScreen? _targetCapture;
    private CellReference? _targetCell;
    private string? _targetSheet;
    private DateTime _targetShown, _lastSelectionRead;
    // Where the current reply and each lesson step happen, read from the screenshot taken with the question.
    // Only the window's geometry is kept, never the picture.
    private CapturedScreen? _replyCapture;
    private ScreenTarget? _replyTarget;
    private IReadOnlyList<ScreenTarget?> _stepTargets = [];
    private IReadOnlyList<CellReference> _requestedCells = [];
    private bool _targetPersistent, _applyingTranscript;
    private string _dictationPrefix = "", _lastTranscript = "";
    private int _consumedTranscript;
    private int _turn, _dictation, _highlightVersion;
    private bool _checkingHighlight, _isListening, _finishingDictation, _screenSharingEnabled = true, _selectionEnabled, _selectionBusy;
    private bool _panelOpen, _leftAnchor, _userPositioned, _dragStarted, _closed;
    private Point _dragScreen;
    private double _dragLeft, _dragTop;
    internal bool IsRequestPending => _pendingReply?.Status == "pending";
    internal ConversationSession Session => _session;
    internal ReplyBubbleWindow ReplyBubble => _bubble;
    internal InputBarWindow ComposerWindow => _input;

    public MainWindow() : this(new ConversationSession(), ConversationStore.Fresh(), new CoachClient(), false) { }

    internal MainWindow(ConversationSession session, ConversationStore store, ICoachClient coach, bool testing,
        IScreenCaptureService? capture = null)
    {
        _session = session; _store = store; _coach = coach; _testing = testing;
        _capture = capture ?? new ScreenCaptureService();
        _screenSharingEnabled = !testing;
        InitializeComponent();
        PipArtView.SetReducedMotion(_reducedMotion);
        _input.SendRequested += () => { if (!IsRequestPending) _ = SubmitAsync(_input.QuestionBox.Text); };
        _input.SendButton.Click += Send_Click;
        _input.MicButton.Click += Talk_Click;
        _input.QuestionBox.TextChanged += (_, _) =>
        {
            // Typing while dictating keeps what was typed; later speech is added after it.
            if (_isListening && !_applyingTranscript) { _dictationPrefix = _input.QuestionBox.Text; _consumedTranscript = _lastTranscript.Length; }
            _saveDraft.Stop(); _saveDraft.Start();
        };
        _input.Moved += PositionBubble;
        _input.SizeChanged += (_, _) => _input.Place();
        _bubble.ReducedMotion = _reducedMotion;
        _bubble.PageChanged = ClearHighlight;
        _bubble.Focus = step => { PointAt(step < 0 ? _replyTarget : step < _stepTargets.Count ? _stepTargets[step] : null, step < 0); WatchLesson(); };
        _bubble.Ask = question => _ = SubmitAsync(question);
        _bubble.Celebrate = () => Wave(TimeSpan.FromSeconds(1.6));
        _bubble.AskSomethingElse = OpenConversation;
        // Back at rest, Pip's resting face returns, with its playful moves (wink, dance, stretch, peekaboo).
        _bubble.Dismissed = () => PipArtView.SetExpression(QuestionIntent.QuickFact);
        _bubble.SizeChanged += (_, _) => PositionBubble();
        LocationChanged += (_, _) => PositionBubble();
        _speechInput.TranscriptChanged += OnTranscriptChanged;
        _speechInput.RecognitionFailed += OnRecognitionFailed;
        _saveDraft.Tick += (_, _) => { _saveDraft.Stop(); SaveConversation(); };
        _watchTarget.Tick += WatchTarget;
        _watchTarget.Tick += WatchSelection;
        _clickTimer.Tick += (_, _) => PollLesson();
        _wave.Tick += (_, _) => { _wave.Stop(); PipArtView.SetWaving(false); _teachingPip?.Pip.SetWaving(false); };
        LayoutCompanion();
        Loaded += (_, _) =>
        {
            _input.Owner = this; _bubble.Owner = this;
            if (!testing) { _capture.StartTracking(); _watchTarget.Start(); }
        };
    }

    /// <summary>On launch: the opening plays, then Pip settles in its corner, waves and asks how it can help.</summary>
    internal void ShowWithIntro()
    {
        Opacity = 0;
        Show();
        UpdateLayout();
        var home = new Rect(PipArtView.PointToScreen(new Point()), PipArtView.PointToScreen(new Point(PipArtView.ActualWidth, PipArtView.ActualHeight)));
        var dpi = VisualTreeHelper.GetDpi(this);
        _intro = new IntroWindow(new Rect(home.X / dpi.DpiScaleX, home.Y / dpi.DpiScaleY, home.Width / dpi.DpiScaleX, home.Height / dpi.DpiScaleY), _reducedMotion);
        _intro.Play(() =>
        {
            _intro = null;
            if (_closed) return;
            Opacity = 1;
            OpenConversation();
            Wave(TimeSpan.FromSeconds(2.4));
            Greet();
            if (!_testing && !Profile.OnboardingComplete) ShowProfile();
        });
    }

    internal void OpenConversation()
    {
        _capture.RememberForeground();
        // Opening/focusing a view must never cancel a turn or replace its messages.
        _panelOpen = true;
        LayoutCompanion();
        _input.Show(); _input.Place();
        _bubble.Resume(); PositionBubble();
        Dispatcher.BeginInvoke(DispatcherPriority.Input, () =>
        {
            if (_closed || !_panelOpen || !IsVisible) return;
            if (!_testing) _input.Activate(); // tests must never take the keyboard
            _input.QuestionBox.Focus();
            if (_lastTargetBounds is { } target) UpdateTeachingCompanion(target);
        });
    }

    internal void MinimiseConversation()
    {
        _panelOpen = false;
        StopTeachingCompanion();
        _input.Hide(); _bubble.Hide();
        LayoutCompanion();
    }

    private void LayoutCompanion()
    {
        var oldX = Canvas.GetLeft(CompanionPanel) + CompanionPanel.Width / 2;
        var oldY = Canvas.GetTop(CompanionPanel) + PipArtView.Height / 2;
        var work = SystemParameters.WorkArea;
        CompanionPanel.Width = PipArtView.Width + 14;
        Width = CompanionPanel.Width + 12; Height = PipArtView.Height + 36;
        Canvas.SetLeft(CompanionPanel, 6); Canvas.SetTop(CompanionPanel, 4);
        if (_userPositioned)
        {
            Left += oldX - (Canvas.GetLeft(CompanionPanel) + CompanionPanel.Width / 2);
            Top += oldY - (Canvas.GetTop(CompanionPanel) + PipArtView.Height / 2);
        }
        else
        {
            Left = _leftAnchor ? work.Left + 12 : work.Right - Width - 12;
            Top = work.Bottom - Height - 12;
        }
        ClampPosition();
        PositionBubble();
    }

    private void ClampPosition()
    {
        var area = SystemParameters.WorkArea;
        Left = Math.Clamp(Left, area.Left, Math.Max(area.Left, area.Right - Width));
        Top = Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - Height));
    }

    private void Character_Pressed(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        _dragScreen = CharacterButton.PointToScreen(e.GetPosition(CharacterButton));
        _dragLeft = Left; _dragTop = Top; _dragStarted = false;
        CharacterButton.CaptureMouse();
        e.Handled = true;
    }

    private void Character_Dragging(object sender, MouseEventArgs e)
    {
        if (!CharacterButton.IsMouseCaptured || e.LeftButton != MouseButtonState.Pressed) return;
        var now = CharacterButton.PointToScreen(e.GetPosition(CharacterButton));
        var dpi = VisualTreeHelper.GetDpi(this);
        var dx = (now.X - _dragScreen.X) / dpi.DpiScaleX;
        var dy = (now.Y - _dragScreen.Y) / dpi.DpiScaleY;
        if (!_dragStarted && Math.Abs(dx) < SystemParameters.MinimumHorizontalDragDistance && Math.Abs(dy) < SystemParameters.MinimumVerticalDragDistance) return;
        _dragStarted = _userPositioned = true;
        Left = _dragLeft + dx; Top = _dragTop + dy;
        ClampPosition(); e.Handled = true;
    }

    private void Character_Released(object sender, MouseButtonEventArgs e)
    {
        if (!CharacterButton.IsMouseCaptured || e.ChangedButton != MouseButton.Left) return;
        CharacterButton.ReleaseMouseCapture();
        if (!_dragStarted) OpenConversation();
        else
        {
            var center = Left + Canvas.GetLeft(CompanionPanel) + CompanionPanel.Width / 2;
            var anchor = center < SystemParameters.WorkArea.Left + SystemParameters.WorkArea.Width / 2;
            if (anchor != _leftAnchor) { _leftAnchor = anchor; LayoutCompanion(); }
        }
        e.Handled = true;
    }

    private void Character_Click(object sender, RoutedEventArgs e) => OpenConversation();

    /// <summary>The names of buttons, tabs and text in the shared window (UI Automation, then Windows OCR of the picture
    /// already taken), so the AI names places that really exist there and F2L can find them exactly.</summary>
    private static async Task<IReadOnlyList<string>> ScreenNamesAsync(CapturedScreen? captured, CancellationToken token)
    {
        if (captured is not { JpegBytes.Length: > 0 }) return [];
        try
        {
            // Both at once, and the control search kept short: this runs before the question is sent.
            var controls = TargetSnap.ControlsAsync(captured.SourceWindow, token, seconds: 0.8);
            var lines = ScreenText.ReadAsync(captured);
            await Task.WhenAll(controls, lines);
            return [.. controls.Result.Select(control => control.Name), .. lines.Result.Select(line => string.Join(" ", line.Select(word => word.Text)))];
        }
        catch (Exception error) when (error is not OperationCanceledException) { return []; }
    }

    /// <summary>The app the screenshot shows, such as "chrome", so a question about another tool is taught from there.</summary>
    private static string? AppName(CapturedScreen? captured)
    {
        if (captured is null) return null;
        try { using var process = System.Diagnostics.Process.GetProcessById((int)captured.SourceProcess); return process.ProcessName; }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException) { return null; }
    }

    private async void Send_Click(object sender, RoutedEventArgs e)
    {
        if (IsRequestPending) { CancelCurrentTurn(); Say("Stopped. Ask me again when you’re ready."); }
        else await SubmitAsync(_input.QuestionBox.Text);
    }

    /// <summary>Pip says a short line in its card: a greeting, a problem, or what it is doing. Notices and problems come
    /// with Pip's curious emote; pass another for greetings and progress.</summary>
    private void Say(string line, PipEmote emote = PipEmote.Curious, params ReplyBubbleWindow.Choice[] choices)
    {
        _bubble.Say(line, emote, choices); PositionBubble();
    }

    /// <summary>"How can I help you, Alex?" with what they chose to learn, to pick from. Nothing starts until they choose.</summary>
    private void Greet()
    {
        if (Profile.Profile is not { PersonalizationEnabled: true } profile) { Say(Greeting, PipEmote.Hello); return; }
        var name = profile.Name.Trim();
        var topics = (profile.Learning ?? []).Take(3).ToArray();
        if (topics.Length == 0)
            Say(name.Length == 0 ? Greeting : $"How can I help you, {name}?", PipEmote.Hello, new ReplyBubbleWindow.Choice("Choose what to learn", true, ShowProfile));
        else
            Say(name.Length == 0 ? "What would you like to learn today?" : $"What would you like to learn today, {name}?", PipEmote.Hello,
                [.. topics.Select(topic => new ReplyBubbleWindow.Choice(topic, true, () => _ = SubmitAsync(LearnerProfile.LessonQuestion(topic)))),
                 new ReplyBubbleWindow.Choice("Change what I learn", false, ShowProfile)]);
    }

    private void Wave(TimeSpan duration)
    {
        _wave.Stop();
        PipArtView.SetWaving(true); _teachingPip?.Pip.SetWaving(true);
        _wave.Interval = duration; _wave.Start();
    }

    internal async Task SubmitAsync(string question)
    {
        if (_isListening || _finishingDictation) { Say("Tap ■ to finish speaking first."); return; }
        var clean = question.Trim();
        if (clean.Length == 0) return;
        // Choose the external app before focusing or hiding Pip. Use this same identity for the whole capture.
        var appToCapture = _screenSharingEnabled ? _capture.GetTarget() : null;
        _selectionEnabled = false; _bubble.UpdateSelection(null, "");
        CancelCurrentTurn();
        ClearHighlight();
        ForgetPlaces();
        var turn = ++_turn;
        var cancellation = new CancellationTokenSource();
        var token = cancellation.Token;
        _turnCancellation = cancellation;
        var entry = _session.Begin(clean);
        _pendingReply = entry;
        Say("Thinking…", PipEmote.Thinking);
        _input.QuestionBox.Clear();
        OpenConversation();
        SetBusy(true);
        SaveConversation();
        var intent = QuestionIntentClassifier.Classify(clean);
        _questionIntent = intent;
        PipArtView.SetExpression(intent);
        CapturedScreen? captured = null;
        string? screenUnavailable = null;
        try
        {
            var cells = CellReference.Find(clean);
            var directCellRequest = cells.Count == 1 && CellReference.IsPointingOnly(clean);
            if (!_coach.IsConfigured && !directCellRequest)
                throw new CoachRequestException(_coach.NotConfigured);
            if (_screenSharingEnabled)
            {
                try { captured = await CaptureCurrentAppAsync(appToCapture, token); }
                catch (ScreenCaptureException error) { screenUnavailable = error.Message; }
            }
            if (turn != _turn) return;
            ExcelContext? context = null;
            if (_screenSharingEnabled && appToCapture is not null && NativeDesktop.ClassName(appToCapture.Window) == "XLMAIN")
            {
                context = await _excel.ReadSelectionAsync(appToCapture, token);
                if (turn != _turn) return;
                if (_screenSharingEnabled)
                {
                    _selectionEnabled = true;
                    _bubble.UpdateSelection(context, context?.DisplayLine ?? SelectionUnavailable);
                }
                else context = null;
            }
            else { _selectionEnabled = false; _bubble.UpdateSelection(null, ""); }
            CoachAnswer answer;
            ExcelTargetResult? exact = null;
            CellReference? exactCell = null;
            if (directCellRequest)
            {
                exactCell = cells[0];
                exact = captured is null
                    ? new(null, screenUnavailable ?? "Screen sharing is paused. Turn it on in Pip's menu so I can verify the cell.")
                    : await _excel.ResolveAsync(captured, exactCell, token);
                answer = new CoachAnswer(exact.Verified
                    ? $"Select {exactCell.Address}: column {new string(exactCell.Address.TakeWhile(char.IsLetter).ToArray())}, row {exactCell.Row}."
                    : exact.Message, null);
            }
            else
            {
                var names = await ScreenNamesAsync(captured, token);
                answer = await _coach.AnswerAsync(ExcelContext.Compose(clean, context, Profile.Profile, AppName(captured), names, AIToolLibrary.Shared), _session.ProviderHistory(entry.TurnId), captured?.JpegBytes,
                    captured is null ? null : "image/jpeg", token);
            }
            token.ThrowIfCancellationRequested();
            if (turn != _turn) return;
            entry.Text = answer.Text;
            entry.Status = "complete";
            _pendingReply = null;
            SetBusy(false);
            // Remember where the reply and each step happen; showing a page sends Pip there.
            _replyCapture = captured is null ? null : captured with { JpegBytes = [] };
            // A step or reply the AI left without a place still points at what it names.
            _replyTarget = answer.PlaceForReply;
            _stepTargets = answer.PlacesForSteps;
            _requestedCells = cells;
            _bubble.ShowReply(answer.Reply, answer.Steps);
            PositionBubble();
            if (exact is { Verified: true, Bounds: { } bounds } && captured is not null && exactCell is not null)
                ShowTarget(captured, bounds, true, exactCell, exact.Sheet);
            SaveConversation();
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { _session.Stop(entry); }
        catch (Exception error)
        {
            if (turn != _turn || _closed) return;
            entry.Text = error is CoachRequestException or ScreenCaptureException ? error.Message : "I couldn't finish that request. Please try again.";
            entry.Status = "error";
            Say(entry.Text);
        }
        finally
        {
            if (captured is not null) Array.Clear(captured.JpegBytes);
            if (turn == _turn && !_closed)
            {
                _pendingReply = null;
                _turnCancellation = null;
                SetBusy(false);
                SaveConversation();
            }
            cancellation.Dispose();
        }
    }

    internal void CancelCurrentTurn()
    {
        _turn++;
        _turnCancellation?.Cancel();
        _turnCancellation = null;
        _session.Stop(_pendingReply);
        _pendingReply = null;
        StopDictation();
        SetBusy(false);
        SaveConversation();
    }

    private void SetBusy(bool busy)
    {
        PipArtView.SetThinking(busy);
        _input.SendButton.Content = busy ? "■" : "↑";
        _input.SendButton.ToolTip = busy ? "Stop" : "Send · Enter";
        _input.SendButton.IsEnabled = !_isListening && !_finishingDictation;
        _input.MicButton.IsEnabled = !_finishingDictation;
    }

    private async Task<CapturedScreen> CaptureCurrentAppAsync(ForegroundApp? app, CancellationToken token)
    {
        if (app is null)
            throw new ScreenCaptureException("No app is selected for screen sharing yet. Click the app you want help with once, then return to Pip.");
        _input.Hide(); _bubble.Hide();
        Hide();
        try
        {
            token.ThrowIfCancellationRequested();
            _capture.PrepareTarget(app);
            await Task.Delay(180, token);
            return _capture.CaptureAppJpeg(app);
        }
        finally
        {
            if (!_closed)
            {
                Show();
                if (_panelOpen) { _input.Show(); _bubble.Resume(); PositionBubble(); }
                var foreground = NativeDesktop.GetForegroundWindow();
                if (_panelOpen && !_testing && (!NativeDesktop.IsExternal(foreground) || NativeDesktop.GetAncestor(foreground, 2) == app.Window))
                {
                    _input.Activate(); _input.QuestionBox.Focus();
                }
            }
        }
    }

    private async void Talk_Click(object sender, RoutedEventArgs e)
    {
        if (_finishingDictation) return;
        if (!_isListening)
        {
            CancelCurrentTurn();
            if (!_speechInput.Start(out var error)) { Say($"The microphone isn’t available: {error}"); return; }
            _dictation++; _isListening = true;
            _dictationPrefix = _input.QuestionBox.Text; _lastTranscript = ""; _consumedTranscript = 0;
            PipArtView.SetListening(true);
            _input.MicButton.Content = "■"; _input.MicButton.ToolTip = "Finish speaking";
            _input.Placeholder = "Listening… tap ■ when you’re done";
            SetBusy(false);
            return;
        }
        var session = _dictation;
        _isListening = false; _finishingDictation = true; PipArtView.SetListening(false); SetBusy(false);
        try
        {
            var final = await _speechInput.StopAsync();
            if (session != _dictation || _closed) return;
            // The recogniser can end with nothing even after showing words; never lose what was already in the box.
            ApplyTranscript(string.IsNullOrWhiteSpace(final) ? _lastTranscript : final);
            _input.Placeholder = _input.QuestionBox.Text.Length == 0 ? "I didn’t catch that. Try again or type." : InputBarWindow.AskPlaceholder;
            _input.QuestionBox.Focus(); _input.QuestionBox.CaretIndex = _input.QuestionBox.Text.Length;
        }
        catch (OperationCanceledException) { }
        finally
        {
            if (session == _dictation && !_closed)
            {
                _finishingDictation = false;
                _input.MicButton.Content = "◉"; _input.MicButton.ToolTip = "Speak your question";
                SetBusy(false);
            }
        }
    }

    private void StopDictation()
    {
        _dictation++;
        if (_isListening || _finishingDictation) _speechInput.Cancel();
        _isListening = _finishingDictation = false;
        PipArtView.SetListening(false);
        _input.MicButton.Content = "◉";
        _input.Placeholder = InputBarWindow.AskPlaceholder;
    }
    private void OnTranscriptChanged(string text) => Dispatcher.BeginInvoke(() =>
    {
        if (!_isListening || _closed) return;
        _lastTranscript = text;
        ApplyTranscript(text);
    });

    /// <summary>What was typed before (or during) dictation, then the words spoken since.</summary>
    private void ApplyTranscript(string transcript)
    {
        var spoken = (transcript.Length > _consumedTranscript ? transcript[_consumedTranscript..] : "").Trim();
        var joined = _dictationPrefix.Length == 0 || spoken.Length == 0 ? _dictationPrefix + spoken
            : _dictationPrefix + (char.IsWhiteSpace(_dictationPrefix[^1]) ? "" : " ") + spoken;
        if (_input.QuestionBox.Text == joined) return;
        _applyingTranscript = true;
        _input.QuestionBox.Text = joined; _input.QuestionBox.CaretIndex = joined.Length;
        _applyingTranscript = false;
    }
    private void OnRecognitionFailed(string error) => Dispatcher.BeginInvoke(() =>
    {
        if (_closed || !_isListening) return;
        StopDictation(); SetBusy(false); Say($"I couldn’t hear you ({error}). You can type instead.");
    });

    internal void NewChat()
    {
        CancelCurrentTurn(); _saveDraft.Stop(); ClearHighlight();
        _session.Entries.Clear(); _store = _store.NextSession(); ForgetPlaces();
        _input.QuestionBox.Clear(); _saveDraft.Stop();
        _selectionEnabled = false; _bubble.UpdateSelection(null, ""); _bubble.Dismiss();
        OpenConversation();
        Greet();
    }

    private void PositionBubble()
    {
        if (!IsLoaded || _closed) return;
        var home = new Rect(PipArtView.PointToScreen(new Point()), PipArtView.PointToScreen(new Point(PipArtView.ActualWidth, PipArtView.ActualHeight)));
        Rect? avoid = _lastTargetBounds is { } target ? Rect.Inflate(TargetSnap.Circle(target), 12, 12) : (Rect?)null;
        _bubble.Follow(_teachingPip?.ScreenBounds ?? home, avoid, PanelPixels());
    }

    /// <summary>Every 1.5 s while a reply about Excel is open: the card shows what is really selected and ticks steps.</summary>
    private async void WatchSelection(object? sender, EventArgs e)
    {
        if (!_selectionEnabled || !_screenSharingEnabled || !_panelOpen || !_bubble.IsShowing || _selectionBusy || _closed ||
            DateTime.UtcNow - _lastSelectionRead < TimeSpan.FromSeconds(1.5)) return;
        var app = _capture.GetTarget();
        if (app is null || NativeDesktop.ClassName(app.Window) != "XLMAIN") return;
        _selectionBusy = true; _lastSelectionRead = DateTime.UtcNow;
        var turn = _turn;
        try
        {
            var context = await _excel.ReadSelectionAsync(app, _lifetime.Token);
            if (turn == _turn && !_closed && _selectionEnabled && _screenSharingEnabled && _capture.GetTarget() == app)
                _bubble.UpdateSelection(context, context?.DisplayLine ?? SelectionUnavailable);
        }
        catch (OperationCanceledException) { }
        finally { _selectionBusy = false; }
    }

    private void SaveConversation() => _store.Save(_session, _input.QuestionBox.Text);

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        // Owned windows (setup, input, card) close before OnClosed; nothing may reopen them from here on.
        _closed = true;
        if (_personalize is not null) _personalize.AppClosing = true;
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        _closed = true;
        CancelCurrentTurn();
        _intro?.Finish();
        // Owned windows may already be closed with their owner.
        try { _bubble.Close(); _input.Close(); } catch (InvalidOperationException) { }
        _saveDraft.Stop(); _watchTarget.Stop(); _clickTimer.Stop(); _wave.Stop(); _lifetime.Cancel();
        ClearHighlight();
        _speechInput.Dispose();
        _capture.Dispose();
        SaveConversation();
        base.OnClosed(e);
    }
}
