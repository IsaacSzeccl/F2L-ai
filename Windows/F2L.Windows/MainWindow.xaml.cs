using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace F2L.Windows;

/// <summary>Resting Pip, the input bar at the bottom centre, Pip's reply card, screen sharing, Excel selection,
/// highlights and the teaching companion. Mirrors CompanionController in Sources/F2L/Companion.swift.
/// Pip is silent: replies are shown, not spoken.</summary>
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
        _bubble.Focus = step => PointAt(step < 0 ? _replyTarget : step < _stepTargets.Count ? _stepTargets[step] : null, step < 0);
        _bubble.Ask = question => _ = SubmitAsync(question);
        _bubble.Celebrate = () => Wave(TimeSpan.FromSeconds(1.6));
        _bubble.AskSomethingElse = OpenConversation;
        _bubble.SizeChanged += (_, _) => PositionBubble();
        LocationChanged += (_, _) => PositionBubble();
        _speechInput.TranscriptChanged += OnTranscriptChanged;
        _speechInput.RecognitionFailed += OnRecognitionFailed;
        _saveDraft.Tick += (_, _) => { _saveDraft.Stop(); SaveConversation(); };
        _watchTarget.Tick += WatchTarget;
        _watchTarget.Tick += WatchSelection;
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

    private async void Send_Click(object sender, RoutedEventArgs e)
    {
        if (IsRequestPending) { CancelCurrentTurn(); Say("Stopped. Ask me again when you’re ready."); }
        else await SubmitAsync(_input.QuestionBox.Text);
    }

    /// <summary>Pip says a short line in its card: a greeting, a problem, or what it is doing.</summary>
    /// <summary>Notices and problems come with Pip's curious emote; pass another for greetings and progress.</summary>
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
                answer = await _coach.AnswerAsync(ExcelContext.Compose(clean, context, Profile.Profile), _session.ProviderHistory(entry.TurnId), captured?.JpegBytes,
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
        var version = _highlightVersion;
        Rect? estimate = target.HasBox ? TargetGeometry.FromScreenshot(capture, target) : null;
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
            // Picture the window as it is now and read it; the picture is dropped straight after.
            var lines = await ReadScreenNowAsync(capture);
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
            }
            PointingLog.Record(target, place is null && estimate is not null ? "model-estimate" : source, place ?? estimate, estimate);
            // Nothing on screen confirmed it (an icon without a visible name): the dashed estimate stays.
            if (place is { } found) ShowTarget(capture, found, true, null, null, persistent: true);
        }
        catch (OperationCanceledException) { }
    }

    /// <summary>A fresh picture of the taught window with F2L's own windows made invisible for a moment, read with
    /// Windows OCR. Only the words and their places are kept.</summary>
    private async Task<IReadOnlyList<IReadOnlyList<ScreenWord>>> ReadScreenNowAsync(CapturedScreen capture)
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
            try { return await ScreenText.ReadAsync(fresh); }
            finally { Array.Clear(fresh.JpegBytes); }
        }
        catch (ScreenCaptureException) { return []; }
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
        _saveDraft.Stop(); _watchTarget.Stop(); _wave.Stop(); _lifetime.Cancel();
        ClearHighlight();
        _speechInput.Dispose();
        _capture.Dispose();
        SaveConversation();
        base.OnClosed(e);
    }
}
