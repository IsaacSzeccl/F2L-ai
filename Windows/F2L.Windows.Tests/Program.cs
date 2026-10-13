using System.IO;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using F2L.Windows;

internal static class Program
{
    private static int _checks;
    private static string _scratch = "";

    [STAThread]
    private static int Main(string[] args)
    {
        _scratch = Path.Combine(Path.GetTempPath(), "F2L-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_scratch);
        var app = new App { StartCompanionOnStartup = false };
        app.InitializeComponent();
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        var exit = 0;
        app.Dispatcher.InvokeAsync(async () =>
        {
            try
            {
                TestCellIdentity(); TestGeometry(); TestPersistence(); TestForegroundMemory();
                TestDirectTeaching(); TestNamedPlaces(); TestClickWatch(); TestAIToolLibrary(); TestStepGoals(); TestZoomLocate(); TestCompanionPlacement(); TestSpriteTextures(); TestProviderParsing();
                await TestProfilesAsync();
                await TestCoachRetriesAsync();
                await TestOverlayAsync();
                await TestTeachingCompanionAsync();
                await TestWindowAsync(args.FirstOrDefault(a => !a.StartsWith("--")));
                await TestComposerCaptureAsync();
                Console.WriteLine($"PASS: {_checks} checks; no API requests, microphone access, or workbook changes.");
                if (args.Contains("--excel-smoke")) await ExcelSmoke.RunAsync();
                if (args.Contains("--provider-smoke"))
                {
                    var coach = new CoachClient();
                    if (!coach.IsConfigured) Console.WriteLine("Provider check skipped: no local API key configured.");
                    else
                    {
                        var reply = await coach.AnswerAsync("How do I add the numbers in A1 through A5 in Excel? Give only the next step.", [], null, null, CancellationToken.None);
                        Console.WriteLine("Live teaching reply: " + reply.Reply);
                        Check(reply.Reply.Contains("SUM", StringComparison.OrdinalIgnoreCase) && reply.Reply.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length <= 55,
                            "live reply provides the requested formula concisely");
                        // A follow-up with history used to come back blank from JSON mode ("I couldn't form a reply").
                        var followUp = await coach.AnswerAsync("Hey please teach me how to build a pi chart in excel",
                            [("user", "How do I add the numbers in A1 through A5 in Excel? Give only the next step."), ("assistant", reply.Reply)],
                            null, null, CancellationToken.None);
                        Console.WriteLine("Live follow-up reply: " + followUp.Reply);
                        Check(followUp.Reply.Length > 20, "live follow-up with history gets a real reply");
                    }
                }
            }
            catch (Exception error) { Console.Error.WriteLine(error); exit = 1; }
            finally { app.Shutdown(); }
        });
        app.Run();
        return exit;
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("FAIL: " + message);
        _checks++;
    }

    private static async Task TestProfilesAsync()
    {
        var profile = new LearnerProfile { Name = "Alex", Role = "Operations", Goal = "Review weekly figures.", Focus = "analyze", ExistingTools = ["excel"] };
        var store = new ProfileStore(Path.Combine(_scratch, "profile.json"));
        Check(!store.Load().OnboardingComplete, "missing profile offers first-time setup");
        var plan = StarterPlan.Draft(profile);
        store.Save(new() { Profile = profile, Plan = plan, OnboardingComplete = true });
        Check(store.Load().Profile?.Role == "Operations" && store.Load().Plan?.Source == "local", "role and local plan survive a fresh load");
        var learner = new LearnerProfile { Focus = "analyze", Learning = [" Pivot tables ", "pivot tables", "", "a", "b", "c", "d", "e", "f"] }.Normalized();
        Check(learner.Learning.Length == LearnerProfile.MaxLearning && learner.Learning[0] == "Pivot tables", "what they want to learn is tidied and capped");
        Check(learner.BackgroundJson.Contains("\"learning\":[\"Pivot tables\""), "what they want to learn is sent with the background");
        var ideas = LearnerProfile.LearningIdeas(new LearnerProfile { Focus = "analyze", Learning = ["My own topic"] }, plan);
        Check(ideas[0] == "My own topic" && ideas.Contains("Pivot tables") && ideas.Distinct().Count() == ideas.Length, "their own topics come first, without repeats");
        var older = System.Text.Json.JsonSerializer.Deserialize<LearnerProfile>("{\"role\":\"Ops\"}", ProfileStore.Json)!;
        Check(older.Role == "Ops" && older.Learning.Length == 0, "profiles saved before learning topics still load");
        Check(!plan.Summary.Contains("..") && plan.Tools[0].Id == "excel", "local draft prefers existing tools and handles punctuation");
        Check(profile.CoachingContext.Contains("Operations") && !profile.CoachingContext.Contains("Alex"), "coaching gets explicit background without display name");
        profile.PersonalizationEnabled = false;
        Check(profile.CoachingContext.Length == 0, "opt-out prevents profile context on future questions");
        profile.ExistingTools = ["excel", "excel", "untrusted"];
        Check(profile.Normalized().ExistingTools.SequenceEqual(new[] { "excel" }), "unknown and duplicate tools are removed");
        store.Forget();
        Check(store.Load() is { OnboardingComplete: true, Profile: null, Plan: null }, "forget removes both profile and plan without reopening setup");
        File.WriteAllText(store.FilePath, "broken");
        Check(!store.Load().OnboardingComplete, "corrupt profile recovers to setup");
        var text = JsonSerializer.Serialize(plan with { Source = "spoofed" }, ProfileStore.Json);
        Check(StarterPlan.Parse(text, "DeepSeek").Source == "DeepSeek", "model cannot spoof plan source");
        try { StarterPlan.Parse(text.Replace("excel", "https://untrusted.invalid"), "test"); Check(false, "invented tool should be rejected"); }
        catch (CoachRequestException) { Check(true, "invented tool is rejected"); }
        foreach (var provider in Enum.GetValues<Provider>())
        {
            var body = CoachClient.RequestBody(StarterPlan.Question(profile), [], null, null, true, provider, systemPrompt: StarterPlan.SystemPrompt);
            using var json = JsonDocument.Parse(body);
            Check(!body.Contains("image_url") && !body.Contains("base64") && json.RootElement.GetProperty("messages").GetArrayLength() == (provider == Provider.Claude ? 1 : 2), "starter plan is text-only with no conversation history");
        }
        var stub = new StubHandler(Completion(text));
        var result = await new CoachClient(new HttpClient(stub), () => "sk-test").StarterPlanAsync(profile, CancellationToken.None);
        Check(result.Source == "DeepSeek" && stub.Bodies.Count == 1 && !stub.Bodies[0].Contains("Alex"), "starter plan uses the selected client and omits display name");
        // Closing setup writes only the skip marker, never an unfinished profile.
        File.Delete(store.FilePath);
        var window = new PersonalizeWindow(store, new CoachClient(new HttpClient(new StubHandler()), () => ""));
        window.Show(); window.Close();
        Check(store.Load() is { OnboardingComplete: true, Profile: null, Plan: null }, "skip setup is persisted without a partial profile");
    }

    private static void TestCellIdentity()
    {
        Check(CellReference.Parse("A1") == new CellReference("A1", 1, 1), "A1 is first column and first row");
        Check(CellReference.Parse("b1") == new CellReference("B1", 1, 2), "B1 is second column");
        Check(CellReference.Parse("$AA$12") == new CellReference("AA12", 12, 27), "absolute reference");
        Check(CellReference.Parse("XFD1048576")?.Column == 16384, "Excel upper bound");
        foreach (var invalid in new[] { "A0", "A1048577", "XFE1", "A1oops", "word", "A1:B1", "Sheet2!A1" })
            Check(CellReference.Parse(invalid) is null, "reject invalid or ambiguous cell " + invalid);
        Check(CellReference.IsPointingOnly("please circle A1 in Excel"), "direct request bypasses model");
        Check(!CellReference.IsPointingOnly("what formula should I put in A1?"), "teaching still reaches model");
        Check(!CellReference.IsPointingOnly("circle A1 and B1"), "multiple cells aren't reduced to one");
        Check(!CellReference.MatchesRequest(CellReference.Parse("B1")!, CellReference.Find("circle A1")), "B1 must never satisfy A1");
        Check(CellReference.MatchesRequest(CellReference.Parse("A1")!, CellReference.Find("circle $A$1")), "normalized matching");
    }

    private static void TestGeometry()
    {
        var capture = new CapturedScreen([], -1920, -200, 1920, 1080, 144, IntPtr.Zero, 0);
        var actual = TargetGeometry.FromScreenshot(capture, new ScreenTarget(100, 100, 200, 200, "test"));
        Check(actual == new Rect(-1728, -92, 192, 108), "negative monitor origin stays in physical pixels");
        var cell = new Rect(-1834, 92, 72, 18);
        foreach (var scale in new[] { 1d, 1.25, 1.5, 2 })
        {
            var outer = TargetGeometry.OverlayBounds(cell, scale);
            outer.Inflate(-8 * scale, -8 * scale);
            Check(outer == cell, $"{scale * 100}% DPI preserves exact cell edges, including short rows");
        }
        Check(!TargetGeometry.IsUsable(Rect.Empty), "empty geometry rejected");
        Check(!TargetGeometry.IsUsable(new Rect(0, 0, 0, 1)), "hidden row or column rejected");
    }

    private static void TestPersistence()
    {
        var session = new ConversationSession();
        var first = session.Begin("Where is A1?"); first.Text = "Column A, row 1."; first.Status = "complete";
        var stopped = session.Begin("Interrupted question"); session.Stop(stopped);
        var pending = session.Begin("Pending question");
        var history = session.ProviderHistory(pending.TurnId);
        Check(history.Count == 2 && history[0].Role == "user" && history[1].Role == "assistant", "provider receives only complete pairs");
        var path = Path.Combine(_scratch, "session.json");
        var store = new ConversationStore(path);
        Check(store.Save(session, "draft survives"), "session saved");
        var restored = new ConversationSession();
        Check(store.Load(restored) == "draft survives", "draft restored");
        Check(restored.Entries.Count == 6 && restored.Entries[0].Text == "Where is A1?", "earlier conversation restored");
        Check(restored.Entries.All(e => e.Status != "pending"), "interrupted app cannot restore a stuck spinner");
        store.Save(session, "newer draft");
        File.WriteAllText(path, "{broken");
        Check(store.Load(new ConversationSession()) == "draft survives", "backup recovers corrupt current file");
        for (var i = 0; i < 260; i++) { var reply = session.Begin("question " + i); reply.Status = "complete"; }
        store.Save(session, "");
        var capped = new ConversationSession(); store.Load(capped);
        Check(capped.Entries.Count == 500 && capped.Entries[0].Role == "user", "500-message cap preserves turn pairs");
    }

    private static string Completion(string content) => JsonSerializer.Serialize(new
    {
        model = "deepseek-flash",
        choices = new[] { new { index = 0, finish_reason = "stop", message = new { role = "assistant", content } } },
    });

    private static void TestProviderParsing()
    {
        var body = JsonDocument.Parse(CoachClient.RequestBody("Hey please teach me how to build a pi chart in excel",
            [("user", "Hey what can you see"), ("assistant", "I can't see your screen right now.")], null, null, true)).RootElement;
        var messages = body.GetProperty("messages");
        Check(messages.GetArrayLength() == 4 && messages[0].GetProperty("content").GetString() == CoachClient.TeachingPrompt &&
            messages[1].GetProperty("content").GetString() == "Hey what can you see" &&
            messages[2].GetProperty("content").GetString() == "{\"reply\":\"I can't see your screen right now.\",\"target\":null}",
            "earlier replies are sent in the JSON shape the model answers in");
        Check(body.GetProperty("response_format").GetProperty("type").GetString() == "json_object" &&
            body.GetProperty("max_tokens").GetInt32() == 650, "first request uses JSON mode");
        Check(!JsonDocument.Parse(CoachClient.RequestBody("q", [], null, null, false)).RootElement.TryGetProperty("response_format", out _),
            "the retry leaves JSON mode off");
        Check(CoachClient.HistoryReply("Type \"=SUM(B2:B10)\" then press Enter.\n\n圈出 A1 / B1") ==
            "{\"reply\":\"Type \\\"=SUM(B2:B10)\\\" then press Enter.\\n\\n圈出 A1 / B1\",\"target\":null}",
            "history replies keep quotes, newlines and Chinese text readable");
        foreach (var blank in new[] { "", "     ", "\n\n", "{\"target\":null}", "{\"reply\":\"   \",\"target\":null}", "{\"reply\":42}" })
            Check(CoachClient.ParseResponse(Completion(blank)) is null, "blank or missing reply asks for a retry");
        var plain = CoachClient.ParseResponse(Completion("Select A1.\n\nThen type a heading."));
        var steps = CoachClient.ReadReply("{\"reply\":\"Select both groups.\",\"steps\":[\"Click A1.\",\"Hold Ctrl and drag D1:D4.\",\"\",7],\"target\":null}");
        Check(steps?.Steps?.Count == 2 && steps.Text.Contains("2. Hold Ctrl and drag D1:D4."), "numbered actions survive model parsing and history");
        var context = ExcelContext.Parse("Budget", "$A$1:$A$4, $D$1:$D$4", "$D$1");
        Check(context?.Areas.SequenceEqual(new[] { "A1:A4", "D1:D4" }) == true && context.PromptLine.Contains("2 separate areas"), "multi-range Excel selection is preserved exactly");
        Check(StepCheck.References("Hold Ctrl and drag from D1 to D4.").SequenceEqual(["D1:D4"]) &&
            StepCheck.References("Select A1-A4, then type =SUM(B1:B4) in C1.").SequenceEqual(["A1:A4", "C1"]), "steps name their cells and ranges");
        const string firstStep = "Click A1, then hold Shift and click A4.", secondStep = "Hold Ctrl and drag from D1 to D4.";
        Check(StepCheck.Check(firstStep, [], ["A1"]).State == StepState.Missing && StepCheck.Check(firstStep, [], ["A1:A4"]).State == StepState.Done,
            "a selection step is ticked only when Excel shows it done");
        Check(StepCheck.Check(secondStep, [firstStep], ["A1:A4", "D1:D4"]).State == StepState.Done &&
            StepCheck.Check(secondStep, [firstStep], ["D1:D4"]).Missing.SequenceEqual(["A1", "A4"]), "forgetting Ctrl drops the first range and Pip says so");
        // Cells are found where Excel's column letters and row numbers meet on screen, even with some headings misread.
        var headings = new[] { "B", "c", "D", "F" }.Select(letter => new ScreenWord(letter, new Rect(100 + (letter.ToUpperInvariant()[0] - 'A') * 64 + 28, 182, 8, 12)))
            .Concat(new[] { 1, 2, 4, 5, 7 }.Select(row => new ScreenWord(row.ToString(), new Rect(70, 200 + (row - 1) * 20 + 4, 12, 12)))).ToArray();
        Check(ScreenText.ExcelCell("D3", headings) is { } d3 && Math.Abs(d3.X - 292) < 0.5 && Math.Abs(d3.Y - 240) < 0.5 && Math.Abs(d3.Width - 64) < 0.5,
            "a cell is placed from the headings read on screen");
        Check(ScreenText.ExcelCell("Z99", headings) is null, "a cell whose headings aren't on screen is never guessed");
        Check(StepCheck.Check("Open Insert and choose a chart.", [], ["A1"]).State == StepState.NotCheckable &&
            StepCheck.Check("Type =SUM(A1:A4) and press Enter.", [], []).State == StepState.NotCheckable, "menus and formulas are left to the learner");
        Check(plain?.Reply == "Select A1.\n\nThen type a heading." && plain.Target is null, "plain text is accepted when JSON mode is off");
        Check(CoachClient.ParseResponse(Completion("```json\n{\"reply\":\"Open Insert.\",\"target\":null}\n```"))?.Reply == "Open Insert." &&
            CoachClient.ParseResponse(Completion("```{\"reply\":\"Open Insert.\",\"target\":null}```"))?.Reply == "Open Insert.", "code fences are removed");
        var answer = CoachClient.ParseResponse(Completion("{\"reply\":\"Sure! Click Insert, then Pie.\",\"target\":{\"left\":100,\"top\":20,\"right\":180,\"bottom\":60,\"label\":\"Insert\"}}"));
        Check(answer?.Reply == "Click Insert, then Pie." && answer.Target == new ScreenTarget(100, 20, 180, 60, "Insert"), "reply and target are read");
        foreach (var unreadable in new[] { "not json", "{\"choices\":[]}", "{\"choices\":[{\"message\":{\"role\":\"assistant\"}}]}", Completion("{\"reply\":\"cut off") })
        {
            try { CoachClient.ParseResponse(unreadable); Check(false, "unreadable response throws"); }
            catch (CoachRequestException error) { Check(error.Message == Provider.DeepSeek.Unreadable(), "unreadable response says so"); }
        }
    }

    private static async Task TestCoachRetriesAsync()
    {
        (string, string)[] history = [("user", "Hey what can you see"), ("assistant", "I can't see your screen right now.")];
        var stub = new StubHandler(Completion("       "), Completion("{\"reply\":\"Select your data, then choose Insert › Pie.\",\"target\":null}"));
        var answer = await new CoachClient(new HttpClient(stub), () => "sk-test")
            .AnswerAsync("Hey please teach me how to build a pi chart in excel", history, null, null, CancellationToken.None);
        Check(answer.Reply == "Select your data, then choose Insert › Pie." && stub.Bodies.Count == 2, "blank JSON-mode reply is asked again");
        Check(stub.Bodies[0].Contains("\"response_format\"") && !stub.Bodies[1].Contains("\"response_format\""), "the retry leaves JSON mode off");

        stub = new StubHandler(Completion("{\"reply\":\"cut"), Completion("Open Insert, then pick Pie."));
        answer = await new CoachClient(new HttpClient(stub), () => "sk-test").AnswerAsync("pie chart?", [], null, null, CancellationToken.None);
        Check(answer.Reply == "Open Insert, then pick Pie." && stub.Bodies.Count == 2, "unreadable reply is asked again");

        stub = new StubHandler(Completion("  "), Completion(""));
        try
        {
            await new CoachClient(new HttpClient(stub), () => "sk-test").AnswerAsync("pie chart?", history, null, null, CancellationToken.None);
            Check(false, "two blank replies throw");
        }
        catch (CoachRequestException error) { Check(error.Message == Provider.DeepSeek.NoReply(), "two blank replies become an error instead of a saved reply"); }

        stub = new StubHandler(HttpStatusCode.Unauthorized, "{\"error\":{\"message\":\"invalid key\"}}");
        try
        {
            await new CoachClient(new HttpClient(stub), () => "sk-test").AnswerAsync("pie chart?", [], null, null, CancellationToken.None);
            Check(false, "401 throws");
        }
        catch (CoachRequestException error)
        {
            Check(error.Message.StartsWith("DeepSeek rejected the configured API key (401).") && stub.Bodies.Count == 1, "provider errors are not retried");
        }

        foreach (var provider in Enum.GetValues<Provider>())
        {
            var credential = "sk-" + new string('a', 48);
            stub = new StubHandler(HttpStatusCode.BadRequest,
                JsonSerializer.Serialize(new { error = new { message = "Rejected credential: " + credential } }));
            try
            {
                await new CoachClient(new HttpClient(stub), () => credential, provider)
                    .AnswerAsync("q", [], null, null, CancellationToken.None);
                Check(false, "bad request throws");
            }
            catch (CoachRequestException error)
            {
                Check(!error.Message.Contains(credential) && !error.Message.Contains("Rejected credential:"),
                    "provider error body never displays credentials");
            }
        }

        stub = new StubHandler();
        try
        {
            await new CoachClient(new HttpClient(stub), () => "").AnswerAsync("q", [], null, null, CancellationToken.None);
            Check(false, "missing key throws");
        }
        catch (CoachRequestException error) { Check(error.Message == Provider.DeepSeek.NotConfigured() && stub.Bodies.Count == 0, "missing key never calls the network"); }
    }

    /// <summary>Answers each request from a queue of canned responses and records what was sent.</summary>
    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Queue<(HttpStatusCode Status, string Body)> _responses = new();
        internal List<string> Bodies { get; } = [];
        internal StubHandler(params string[] bodies) { foreach (var body in bodies) _responses.Enqueue((HttpStatusCode.OK, body)); }
        internal StubHandler(HttpStatusCode status, string body) => _responses.Enqueue((status, body));
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Bodies.Add(request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken));
            var (status, body) = _responses.Count > 0 ? _responses.Dequeue() : (HttpStatusCode.InternalServerError, "");
            return new HttpResponseMessage(status) { Content = new StringContent(body) };
        }
    }

    private static async Task TestOverlayAsync()
    {
        var overlay = new GuideOverlayWindow();
        try
        {
            var target = new Rect(250, 250, 72, 18);
            overlay.ShowTarget(target, true); await Pump();
            var frame = (FrameworkElement)overlay.FindName("TargetFrame");
            var topLeft = frame.PointToScreen(new Point());
            var bottomRight = frame.PointToScreen(new Point(frame.ActualWidth, frame.ActualHeight));
            var circle = TargetSnap.Circle(target);
            Check(Math.Abs(topLeft.X - circle.X) <= 1 && Math.Abs(topLeft.Y - circle.Y) <= 1 &&
                Math.Abs(bottomRight.X - circle.Right) <= 1 && Math.Abs(bottomRight.Y - circle.Bottom) <= 1,
                "the circle is drawn where the target is, at physical pixels");
            Check(circle.Width < target.Width * 1.6 && circle.Height < target.Height * 2.2, "the circle hugs a short cell without covering its neighbours");
            var ribbon = new[] { new ControlCandidate(new Rect(150, 60, 44, 22), "Insert"), new ControlCandidate(new Rect(420, 90, 40, 56), "Insert Pie or Doughnut Chart") };
            Check(TargetSnap.Snap(new Rect(175, 75, 40, 20), "Insert tab", ribbon) == new Rect(150, 60, 44, 22) &&
                TargetSnap.Snap(new Rect(400, 100, 30, 30), "Pie chart", ribbon) == new Rect(420, 90, 40, 56),
                "rough places snap to the real control the app reports");
        }
        finally { overlay.Close(); }
    }

    private static void TestForegroundMemory()
    {
        var excel = new ForegroundApp(new IntPtr(101), 201);
        var word = new ForegroundApp(new IntPtr(102), 202);
        var pip = new IntPtr(103);
        var foreground = excel.Window;
        var valid = true;
        using var tracker = new ForegroundAppTracker(() => foreground,
            handle => handle == excel.Window ? excel : handle == word.Window ? word : null, _ => valid);
        tracker.RememberForeground();
        foreground = pip;
        Check(tracker.GetTarget() == excel, "Pip taking foreground focus retains Excel's identity");
        foreground = word.Window; tracker.Observe(word.Window); foreground = pip;
        Check(tracker.GetTarget() == word, "switching external apps updates the remembered window");
        foreground = IntPtr.Zero;
        Check(tracker.GetTarget() == word, "desktop and transient focus cannot replace the teaching app");
        var pinned = tracker.GetTarget();
        tracker.Observe(excel.Window);
        Check(pinned == word && tracker.GetTarget() == excel, "a pinned request never changes window halfway through");
        valid = false;
        Check(tracker.GetTarget() is null, "closed, minimised or reused window is rejected");
        Check(ComposerKeys.ShouldSend(Key.Enter, ModifierKeys.None, false), "plain Enter sends");
        Check(!ComposerKeys.ShouldSend(Key.Enter, ModifierKeys.Shift, false), "Shift+Enter keeps a newline");
        Check(!ComposerKeys.ShouldSend(Key.Enter, ModifierKeys.Shift | ModifierKeys.Control, false), "Shift combination doesn't accidentally send");
        Check(!ComposerKeys.ShouldSend(Key.Enter, ModifierKeys.None, true), "IME confirmation isn't sent as a question");
        Check(!ComposerKeys.ShouldSend(Key.ImeProcessed, ModifierKeys.None, false), "IME processed keys pass through to typing");
    }

    // Same cases as ZoomedLook on Mac.
    private static void TestZoomLocate()
    {
        var window = new Rect(100, 50, 1400, 900);
        var small = ZoomLocate.Crop(new Rect(600, 400, 30, 20), window);
        Check(small.Width == 420 && small.Height == 280 && small.X + small.Width / 2 == 615 && small.Y + small.Height / 2 == 410, "the crop surrounds the guess");
        var corner = ZoomLocate.Crop(new Rect(105, 55, 20, 20), window);
        Check(corner.X == window.X && corner.Y == window.Y && ZoomLocate.Crop(null, window) == window, "the crop stays in the window");
        Check(ZoomLocate.PixelRect(new Rect(200, 150, 420, 280), window, new Size(2800, 1800)) == new Int32Rect(200, 200, 840, 560), "crops map to the picture's pixels");
        var crop = new Rect(200, 150, 400, 200);
        Check(ZoomLocate.Parse("{\"found\":true,\"left\":100,\"top\":200,\"right\":200,\"bottom\":400}", crop) == new Rect(240, 190, 40, 40), "a found control maps back to the screen");
        Check(ZoomLocate.Parse("{\"found\":false}", crop) is null && ZoomLocate.Parse("{\"found\":true,\"left\":0,\"top\":0,\"right\":1000,\"bottom\":1000}", crop) is null
            && ZoomLocate.Parse("not json", crop) is null, "not found, too big or unreadable gives nothing");
    }

    // Same cases as StepGoals on Mac.
    private static void TestStepGoals()
    {
        Check(StepGoal.Of("Open your browser, such as Safari or Chrome.")?.Type == StepGoal.Kind.Browser && StepGoal.Of("Open Safari.")?.Type == StepGoal.Kind.Browser, "browser steps");
        Check(StepGoal.Of("Open Excel.") is { Type: StepGoal.Kind.App } excel && excel.Names.SequenceEqual(["excel"]), "app steps");
        Check(StepGoal.Of("Go to chatgpt.com and click Sign up.") is { Type: StepGoal.Kind.Site } chat && chat.Names.SequenceEqual(["chatgpt.com", "chatgpt"]), "site steps");
        Check(StepGoal.Of("Open the Insert tab.") is null && StepGoal.Of("Click New page in the left sidebar.") is null, "places inside an app are not goals");
        var site = StepGoal.Of("Go to chatgpt.com")!;
        Check(site.IsMet("chrome", "ChatGPT - Google Chrome") && !site.IsMet("chrome", "Google") && !site.IsMet("notepad", "chatgpt ideas"), "a site counts only open in a browser");
        Check(StepGoal.Of("Open Excel.")!.IsMet("EXCEL", "Book1") && new StepGoal(StepGoal.Kind.Browser, []).IsMet("msedge", "New tab"), "apps in front are recognised");
    }

    // Same cases as AIToolLibraries on Mac.
    private static void TestAIToolLibrary()
    {
        var library = AIToolLibrary.Shared;
        Check(library.Tools.Count >= 60 && library.Checked.Length > 0 && library.Tools.Select(t => t.Id).Distinct().Count() == library.Tools.Count,
            "the embedded AI tools library loads");
        Check(new[] { "excel", "notion", "canva", "notebooklm", "zapier", "copilot" }.All(id => library.Find(id) is not null), "starter-plan tools are in the library");
        foreach (var (question, ids) in new[] { ("How do I set up n8n with Notion?", new[] { "notion", "n8n" }), ("i would like to learn how to use tencent workbuddy", new[] { "workbuddy" }),
            ("Teach me Grok", new[] { "grok" }), ("怎么用豆包", new[] { "doubao" }), ("How do I use make.com?", new[] { "make" }), ("Make a chart from this", Array.Empty<string>()),
            ("Find the gamma value", Array.Empty<string>()), ("Open Gamma app", new[] { "gamma" }) })
            Check(library.Mentioned(question).Select(t => t.Id).SequenceEqual(ids), $"finds the tools named in: {question}");
        var notes = library.ReferenceNotes("How do I start with n8n?");
        Check(notes.Contains("n8n (Automation)") && notes.Contains("Official site: https://n8n.io.") && !notes.Contains("may fit this learner"), "tool notes come from the library");
        var learner = new LearnerProfile { Focus = "create" };
        Check(AIToolLibrary.AsksForRecommendation("Which AI tool should I use for slides?") && library.Fitting(learner).All(t => t.GoodFor.Contains("create"))
            && library.ReferenceNotes("Which AI tool should I use for slides?", learner).Contains("may fit this learner"), "recommendations fit the learner");
        Check(AIToolLibrary.Load(null).Tools.Select(t => t.Id).SequenceEqual(["excel", "notion", "canva", "notebooklm", "zapier", "copilot"]), "a missing library falls back");
    }

    // Same cases as ClickWatching on Mac.
    private static void TestClickWatch()
    {
        var place = new Rect(100, 100, 80, 24);
        var watch = new ClickWatch();
        Check(!watch.Pressed(false, new Point(140, 112), place) && watch.Pressed(true, new Point(140, 112), place)
            && !watch.Pressed(true, new Point(140, 112), place), "a press on the circle counts once");
        watch.Pressed(false, new Point(0, 0), place);
        Check(watch.Pressed(true, new Point(92, 112), place), "a press just outside the drawn circle still counts");
        watch.Pressed(false, new Point(0, 0), place);
        Check(!watch.Pressed(true, new Point(400, 400), place) , "a press far away does not count");
        watch.Pressed(false, new Point(0, 0), place);
        Check(!watch.Pressed(true, new Point(140, 112), place, onOwnWindow: true) , "a press on Pip's own windows does not count");
        foreach (var (step, finishes) in new[] { ("Click New page.", true), ("Open the Insert tab.", true), ("Type your email in the box.", false),
            ("Drag from A1 to A4.", false), ("Hold Command and click D1.", true), ("Hold Command and drag from D1 to D4.", false), ("Paste the text.", false) })
            Check(ClickWatch.FinishesOnClick(step) == finishes, $"click finishing: {step}");
        Check(ClickWatch.RequiredKeys("Click A1, then hold Shift and click A4.").SetEquals(["shift"]) && ClickWatch.RequiredKeys("Hold Ctrl and click D1.").SetEquals(["control"])
            && ClickWatch.RequiredKeys("Click New page.").Count == 0, "keys to hold are read from the step");
        Check(ClickWatch.IsTypingStep("Enter 100 in B2.") && !ClickWatch.IsTypingStep("Click Share."), "typing steps are recognised");
        var typing = new TypingWatch(); var start = DateTime.UtcNow;
        Check(!typing.Observe(new(0, 1), start) && !typing.Observe(new(3, 2), start.AddSeconds(0.5)) && !typing.Observe(new(5, 3), start.AddSeconds(1))
            && !typing.Observe(new(5, 3), start.AddSeconds(2)) && typing.Observe(new(5, 3), start.AddSeconds(2.6)) && !typing.Observe(new(5, 3), start.AddSeconds(4)),
            "typing ticks once the box has new text and the learner pauses");
        var names = ScreenNames.Pick(new[] { "Share", "share", " New page ", "x", "12", new string('a', 50), "Insert" }.Concat(Enumerable.Range(0, 200).Select(i => $"Item {i}")));
        Check(names.Take(3).SequenceEqual(["Share", "New page", "Insert"]) && names.Count == ScreenNames.Limit && ScreenNames.Line([]) == "", "screen names are tidy and bounded");
    }

    // Same cases as NamedPlaces on Mac.
    private static void TestNamedPlaces()
    {
        foreach (var (text, name) in new[] {
            ("Click the Japan tile in the Recents row.", "Japan"), ("Open the Insert tab.", "Insert"),
            ("Click Pause for 15 min to stop for a while.", "Pause"), ("You can find it in the Home tab.", "Home"),
            ("Choose \u201CRecommended Charts\u201D from the list.", "Recommended Charts"), ("Hold Shift and click A4.", "A4"),
            ("Select A1:A4 first.", "A1:A4") })
            Check(NamedPlace.Label(text) == name, $"finds the named place in: {text}");
        foreach (var text in new[] { "This is a VPN app window. It shows you connected through Melbourne.", "Press Command+C to copy.",
            "Click the empty cell under your numbers, then type =SUM(B2:B10).", "Hold Command and drag from D1 to D4." })
            Check(NamedPlace.Label(text) is null, $"names nothing in: {text}");
        Check(NamedPlace.Target("Click A4.")?.Cell == "A4" && NamedPlace.Target("Select A1:A4.")?.Cell == "A1", "named cells are checked with Excel");
        var japan = new ScreenTarget(1, 1, 9, 9, "Japan"); var insert = new ScreenTarget(2, 2, 8, 8, "Insert");
        Check(new CoachAnswer("Switch to Japan.", japan, ["Click the Japan tile."]).PlacesForSteps[0] == japan, "the only step borrows the reply's place");
        var places = new CoachAnswer("Insert a chart.", insert, ["Open the Insert tab.", "Click Recommended Charts.", "Click OK."], [null, null, japan]).PlacesForSteps;
        Check(places[0] == insert && places[1]?.Label == "Recommended Charts" && places[2] == japan, "steps without a place still point somewhere");
        Check(new CoachAnswer("Click the Japan tile in the Recents row.", null).PlaceForReply?.Label == "Japan"
            && new CoachAnswer("This is a VPN app.", null).PlaceForReply is null, "a reply that says what to click points at it");
    }

    private static void TestDirectTeaching()
    {
        Check(TeachingReply.Clean("Great question! Sure! Select A1. Let me know if you need more help.") == "Select A1.", "stock preamble and trailing invitation removed");
        Check(TeachingReply.Clean("Enter =SUM(A1:A5). This replaces the current cell value.") == "Enter =SUM(A1:A5). This replaces the current cell value.", "formulas and essential warnings preserved");
        Check(TeachingReply.Clean("Select the column named Sure.") == "Select the column named Sure.", "cleanup does not remove real instruction text");
        Check(QuestionIntentClassifier.Classify("What is SUM?") == QuestionIntent.QuickFact, "short questions aren't automatically treated as confusion");
        Check(QuestionIntentClassifier.Classify("Which one?") == QuestionIntent.ClarificationNeeded, "genuine ambiguity retains curious expression");
    }

    private static void TestCompanionPlacement()
    {
        foreach (var scale in new[] { 1d, 1.25, 1.5, 2 })
        {
            var work = new Rect(-1600, -100, 1600 * scale, 900 * scale);
            foreach (var point in new[] { new Point(work.Left + 8, work.Top + 8), new Point(work.Right - 130 * scale, work.Top + 8),
                new Point(work.Left + 8, work.Bottom - 50 * scale), new Point(work.Right - 130 * scale, work.Bottom - 50 * scale),
                new Point(work.Left + work.Width / 2, work.Top + work.Height / 2) })
            {
                var target = new Rect(point.X, point.Y, 80 * scale, 24 * scale);
                var spot = CompanionPlacement.Choose(target, work, new Size(112 * scale, 119 * scale), Rect.Empty, new(-10000, -10000), scale);
                Check(spot is not null && work.Contains(spot.Bounds) && !spot.Bounds.IntersectsWith(CompanionPlacement.ProtectedArea(target, scale)),
                    "Pip fits near edge targets without covering the working area at " + scale);
            }
        }
        var small = new Rect(0, 0, 100, 100);
        Check(CompanionPlacement.Choose(new(20, 20, 60, 60), small, new(112, 119), Rect.Empty, new(-1, -1), 1) is null,
            "no safe space hides the follower instead of covering the task");
        var area = new Rect(0, 0, 1200, 800);
        var cell = new Rect(500, 350, 80, 24);
        var panel = new Rect(600, 100, 500, 650);
        var candidate = CompanionPlacement.Choose(cell, area, new(112, 119), panel, new(-1, -1), 1);
        Check(candidate is not null && !candidate.Bounds.IntersectsWith(panel), "Pip avoids the conversation panel");
        Check(candidate is not null && (candidate.Direction switch
        {
            PointingDirection.Right => candidate.Bounds.Right <= cell.Left,
            PointingDirection.Left => candidate.Bounds.Left >= cell.Right,
            PointingDirection.Up => candidate.Bounds.Top >= cell.Bottom,
            PointingDirection.Down => candidate.Bounds.Bottom <= cell.Top,
            _ => false,
        }), "the selected pose points from Pip's safe slot toward the cell");
        var sprite = new Rect(300, 300, 100, 110);
        Check(CompanionPlacement.ShouldYield(sprite, cell, new(295, 340), Rect.Empty, 1), "pointer proximity clears the artwork");
        Check(CompanionPlacement.ShouldYield(sprite, cell, new(-1, -1), new(380, 330, 2, 20), 1), "nearby text caret clears the artwork");
        Check(!CompanionPlacement.ShouldYield(sprite, cell, new(10, 10), Rect.Empty, 1), "Pip stays visible when the working area is clear");
    }

    private static void TestSpriteTextures()
    {
        for (var seed = 0; seed < 16; seed++)
        {
            var activities = new HashSet<int>();
            for (var cycle = 0; cycle < 4; cycle++)
            {
                var start = cycle * 12_000 + 6_000 + (seed * 73 + cycle * 997) % 3_000;
                var first = PipView.PlayfulFrame(start, seed);
                Check(first.HasValue, "idle vignette starts after its quiet lead-in");
                activities.Add(first!.Value / 4);
                Check(PipView.PlayfulFrame(start - 1, seed) is null && PipView.PlayfulFrame(start + 2200, seed) is null,
                    "playful gestures return to rest");
                foreach (var (offset, frame) in new[] { (0, 0), (350, 1), (1000, 2), (1650, 3) })
                    Check(PipView.PlayfulFrame(start + offset, seed) == first + frame, "all four animation frames play in order");
            }
            Check(activities.Count == 4, "all idle activities play without adjacent repeats");
        }
        foreach (var name in new[] { "expressions", "directions", "playful" })
        {
            var atlas = new BitmapImage(new Uri($"pack://application:,,,/F2L.Windows;component/Assets/Pip/{name}.png"));
            var stored = PipSprites.ManifestFrames(name, atlas);
            Check(stored is not null && stored.SequenceEqual(PipSprites.FindFrames(atlas)), "precomputed frames.json matches the scanned atlas");
        }
        foreach (var frames in new[] { PipSprites.Expressions, PipSprites.Directions, PipSprites.Playful })
        {
            Check(frames.Length == 16, "all sixteen generated poses load");
            foreach (var frame in frames)
            {
                var bitmap = new FormatConvertedBitmap(frame.Image, PixelFormats.Bgra32, null, 0);
                var bytes = new byte[bitmap.PixelWidth * bitmap.PixelHeight * 4]; bitmap.CopyPixels(bytes, bitmap.PixelWidth * 4, 0);
                var transparent = 0; var solid = 0;
                for (var i = 3; i < bytes.Length; i += 4) { if (bytes[i] < 10) transparent++; if (bytes[i] > 240) solid++; }
                Check(transparent > 100 && solid > 1000 && frame.Width <= 320 && frame.Height <= 325, "sprite retains real alpha and fits its animation canvas");
            }
        }
        var pip = new PipView(); pip.SetReducedMotion(true);
        pip.SetExpression(QuestionIntent.MultiPart);
        Check(pip.CurrentFrame.StartsWith("expression:4:"), "conceptual question uses generated thoughtful pose");
        pip.SetListening(true);
        Check(pip.CurrentFrame.StartsWith("expression:8:"), "listening uses generated attentive pose");
        pip.SetListening(false); pip.SetPointing(PointingDirection.Left);
        Check(pip.CurrentFrame.StartsWith("direction:0:"), "left target uses generated left pointing pose");
        pip.SetPointing(PointingDirection.Right);
        Check(pip.CurrentFrame.StartsWith("direction:2:"), "right target uses generated right pointing pose");
    }

    private static async Task TestTeachingCompanionAsync()
    {
        var follower = new TeachingCompanionWindow { ReducedMotion = true };
        try
        {
            var target = new Rect(200, 200, 80, 24);
            var first = new CompanionSpot(new(330, 140, 112, 119), PointingDirection.Left);
            follower.Follow(first, target, 1); await Pump();
            Check(follower.ScreenBounds == first.Bounds && !follower.ShowActivated && !follower.IsHitTestVisible,
                "teaching companion occupies its safe slot without taking keyboard focus");
            var second = new CompanionSpot(new(530, 240, 112, 119), PointingDirection.Right);
            follower.Follow(second, new(680, 300, 80, 24), 1); await Pump();
            Check(follower.ScreenBounds == second.Bounds && follower.Pip.CurrentFrame.StartsWith("direction:2:"),
                "moving a target moves Pip and changes its pointing side");
            follower.Pip.SetPointing(PointingDirection.None);
            follower.Pip.SetReducedMotion(false);
            follower.Pip.SetSpeaking(true);
            var speakingFrame = follower.Pip.CurrentFrame;
            await WaitFor(() => follower.Pip.CurrentFrame != speakingFrame);
            Check(follower.Pip.CurrentFrame.StartsWith("expression:"), "loaded Pip changes actual painted frames while speaking");
            follower.Pip.SetReducedMotion(true);
            var stillFrame = follower.Pip.CurrentFrame;
            await Task.Delay(220);
            Check(follower.Pip.CurrentFrame == stillFrame, "reduced motion holds a stable painted pose");
        }
        finally { follower.Close(); }
    }

    private static async Task TestComposerCaptureAsync()
    {
        var screen = new FakeScreen();
        var coach = new RecordingCoach();
        var session = new ConversationSession();
        var window = new MainWindow(session, new ConversationStore(Path.Combine(_scratch, "composer.json")), coach, true, screen);
        try
        {
            window.Show(); window.OpenConversation(); await Pump();
            window.SetScreenSharing(true);
            var question = window.ComposerWindow.QuestionBox;
            question.Text = "Help me with the app I'm using";
            var key = new KeyEventArgs(Keyboard.PrimaryDevice, PresentationSource.FromVisual(question), 0, Key.Enter)
                { RoutedEvent = Keyboard.PreviewKeyDownEvent };
            question.RaiseEvent(key);
            Check(key.Handled && question.Text.Length == 0 && session.Entries.Count == 2,
                "real composer preview event sends Enter once before TextBox consumes it");
            var selected = screen.Selected!;
            screen.Selected = new(new IntPtr(999), 999); // App changed during the capture delay.
            await WaitFor(() => !window.IsRequestPending);
            Check(coach.Requests.Count == 1 && coach.Requests[0].Question.StartsWith("Help me with the app I'm using\n\n(Learner's computer: Windows."),
                "Enter dispatches the typed question to the provider");
            Check(screen.Prepared == selected && screen.Captured == selected,
                "capture uses the same app selected before Pip focuses");
            Check(coach.Requests[0].Image is { Length: > 0 }, "remembered-app image accompanies the question");

            screen.Selected = null;
            await window.SubmitAsync("Can you explain a formula?");
            Check(coach.Requests.Count == 2 && coach.Requests.Last().Image is null && session.Entries.Last().Status == "complete",
                "missing app doesn't prevent a typed question from being sent");
            Check(window.ReplyBubble.CurrentPhrase == "Your question reached the coach.",
                "Pip still answers in its card without a screen image");

            screen.Selected = selected; screen.Fail = true;
            await window.SubmitAsync("What does this button do?");
            Check(coach.Requests.Count == 3 && coach.Requests.Last().Image is null && !window.IsRequestPending,
                "capture failure falls back to text and releases the composer");
            screen.Fail = false;
            await window.SubmitAsync("Try reading the screen again");
            Check(coach.Requests.Last().Image is { Length: > 0 } && session.Entries.Last().Status == "complete",
                "capture and sending recover on the next question");

            screen.Selected = null;
            await window.SubmitAsync("circle A1");
            Check(coach.Requests.Count == 4 && session.Entries.Last().Text.Contains("No app is selected"),
                "exact cell request never invents geometry when no app is available");
        }
        finally { window.Close(); }
        Check(screen.Disposed, "closing Pip releases foreground tracking");
    }

    private static async Task WaitFor(Func<bool> done)
    {
        for (var i = 0; i < 60 && !done(); i++) await Task.Delay(50);
        Check(done(), "asynchronous UI action completed");
        await Pump();
    }

    private sealed class FakeScreen : IScreenCaptureService
    {
        internal ForegroundApp? Selected = new(new IntPtr(110), 210);
        internal ForegroundApp? Prepared, Captured;
        internal bool Fail, Disposed;
        public void StartTracking() { }
        public void RememberForeground() { }
        public ForegroundApp? GetTarget() => Selected;
        public void PrepareTarget(ForegroundApp target) => Prepared = target;
        public CapturedScreen CaptureAppJpeg(ForegroundApp target)
        {
            Captured = target;
            if (Fail) throw new ScreenCaptureException("Simulated screenshot failure");
            return new([1, 2, 3], 0, 0, 1280, 720, 96, target.Window, target.Process);
        }
        public void Dispose() => Disposed = true;
    }

    private sealed class RecordingCoach : ICoachClient
    {
        internal List<(string Question, byte[]? Image)> Requests { get; } = [];
        public bool IsConfigured => true;
        public Task<CoachAnswer> AnswerAsync(string question, IReadOnlyList<(string Role, string Content)> history,
            byte[]? imageBytes, string? imageContentType, CancellationToken cancellationToken)
        {
            Requests.Add((question, imageBytes?.ToArray()));
            return Task.FromResult(new CoachAnswer("Your question reached the coach.", null));
        }
    }

    private static async Task TestWindowAsync(string? renderPath)
    {
        var fake = new FakeCoach();
        var session = new ConversationSession();
        var window = new MainWindow(session, new ConversationStore(Path.Combine(_scratch, "window.json")), fake, true);
        window.Show(); window.OpenConversation();
        await Pump();
        var font = (FontFamily)Application.Current.FindResource("UiFont");
        Check(new Typeface(font, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal).TryGetGlyphTypeface(out var glyph)
            && glyph.FamilyNames.Values.Any(v => v.Contains("Inter")), "bundled Inter font actually resolves");

        var first = window.SubmitAsync("Where do I start?");
        Check(window.IsRequestPending, "pending request starts");
        window.MinimiseConversation(); window.OpenConversation(); window.OpenConversation();
        Check(window.IsRequestPending && session.Entries.Count == 2, "clicking Pip preserves pending turn and history");
        fake.Reply(0, "Start with one small step."); await first; await Pump();
        Check(session.Entries.Last().Status == "complete", "reply completes after reopen");
        Check(window.ComposerWindow.SendButton.IsEnabled, "follow-up input is available");
        var old = window.SubmitAsync("Slow question");
        window.CancelCurrentTurn();
        var next = window.SubmitAsync("New question");
        fake.Reply(1, "Obsolete reply"); await old;
        Check(window.IsRequestPending && session.Entries[3].Status == "stopped", "late cancelled reply cannot replace current request");
        fake.Reply(2, "New reply"); await next;
        Check(session.Entries.Last().Text == "New reply", "new turn completes after cancellation");
        var failure = window.SubmitAsync("Failed question"); fake.Fail(3); await failure;
        Check(session.Entries.Last().Status == "error" && !window.IsRequestPending, "failure releases composer");
        var recover = window.SubmitAsync("Try again"); fake.Reply(4, "Recovered."); await recover;
        Check(session.Entries.Last().Text == "Recovered.", "follow-up succeeds after failure");
        var longTask = window.SubmitAsync("Explain each step, please.");
        var passage = string.Join("\n\n", Enumerable.Range(1, 30).Select(i => $"Step {i}. Start by selecting the cell where you want the answer. You can take your time and follow one step at a time."));
        fake.Reply(5, passage); await longTask; await Pump();
        Check(window.ReplyBubble.CurrentPhrase == passage.Split("\n\n")[0], "long replies start with one phrase");
        window.ReplyBubble.GoTo(1);
        Check(window.ReplyBubble.CurrentPhrase == passage.Split("\n\n")[1], "Next advances to the following phrase without losing text");
        window.ReplyBubble.GoTo(0);
        Check(window.ReplyBubble.CurrentPhrase == passage.Split("\n\n")[0], "Previous revisits a phrase");
        window.ReplyBubble.ReducedMotion = true;
        window.ReplyBubble.FinishReveal();
        Check(window.ReplyBubble.IsVisible, "reduced motion keeps the written reply available");
        var composerArea = SystemParameters.WorkArea;
        Check(Math.Abs(window.ComposerWindow.Left + window.ComposerWindow.Width / 2 - composerArea.Left - composerArea.Width / 2) < 1,
            "composer stays at the bottom centre independently of Pip");
        window.MinimiseConversation(); window.OpenConversation(); await Pump();
        Check(session.Entries.Count == 12 && session.Entries[0].Text == "Where do I start?", "minimising never erases previous messages");
        var work = NativeDesktop.WorkAreaAt(new Point(100, 100));
        window.UpdateTeachingCompanion(new Rect(work.Left + 40, work.Top + 40, 80, 24)); await Pump();
        Check(!window.IsPipFollowing, "by default Pip stays in its corner and only the circle shows the place");
        window.SetFollowTargets(true);
        window.UpdateTeachingCompanion(new Rect(work.Left + 40, work.Top + 40, 80, 24)); await Pump();
        Check(window.IsPipFollowing, "with following turned on, Pip stands beside a teaching target");
        window.MinimiseConversation();
        Check(!window.IsPipFollowing && ((FrameworkElement)window.FindName("CompanionPanel")).Visibility == Visibility.Visible,
            "minimising returns Pip so the conversation remains reachable");
        window.OpenConversation(); await Pump();
        window.SetFollowTargets(false);
        Check(!window.IsPipFollowing, "turning following off in Settings keeps Pip at its chosen home");

        // A lesson: one step at a time, ticked from Excel's real selection.
        var lesson = window.ReplyBubble;
        lesson.ShowReply("Select both groups before inserting the chart.", ["Click A1, then hold Shift and click A4.", "Hold Ctrl and drag from D1 to D4."]);
        lesson.FinishReveal();
        Check(lesson.CurrentPhrase == "Click A1, then hold Shift and click A4.", "a lesson starts straight at step 1");
        lesson.UpdateSelection(ExcelContext.Parse("Budget", "$A$1:$A$4", "$A$1"), "Excel has selected A1:A4 · Budget");
        await Task.Delay(1600); await Pump();
        Check(lesson.CurrentPhrase == "Hold Ctrl and drag from D1 to D4.", "a step Excel shows done moves on by itself");
        lesson.GoTo(2); lesson.FinishReveal();
        Check(lesson.CurrentPhrase == "All done. You did every step.", "the lesson ends once every step is done");

        // Render the real WPF reply card; no desktop capture or credentials.
        if (!string.IsNullOrWhiteSpace(renderPath))
        {
            var card = (FrameworkElement)lesson.Content;
            card.UpdateLayout();
            var bitmap = new RenderTargetBitmap((int)Math.Ceiling(card.ActualWidth * 1.5), (int)Math.Ceiling(card.ActualHeight * 1.5), 144, 144, PixelFormats.Pbgra32);
            bitmap.Render(card);
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(renderPath))!);
            var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap));
            using var stream = File.Create(renderPath); png.Save(stream);
            Console.WriteLine("UI preview: " + Path.GetFullPath(renderPath));
        }
        var pending = window.SubmitAsync("A reply that should be cancelled by New chat");
        window.NewChat();
        Check(session.Entries.Count == 0 && !window.IsRequestPending && window.ReplyBubble.CurrentPhrase == MainWindow.Greeting,
            "New chat clears replies and model history, and Pip greets again");
        fake.Reply(6, "Stale reply"); await pending;
        Check(session.Entries.Count == 0 && window.ReplyBubble.CurrentPhrase == MainWindow.Greeting, "a late reply cannot reopen a cleared chat");
        window.Close();
    }

    private static async Task Pump()
    {
        await Application.Current.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
        await Task.Delay(60);
        await Application.Current.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
    }

    private sealed class FakeCoach : ICoachClient
    {
        private readonly List<TaskCompletionSource<CoachAnswer>> _requests = [];
        public bool IsConfigured => true;
        public Task<CoachAnswer> AnswerAsync(string question, IReadOnlyList<(string Role, string Content)> history,
            byte[]? imageBytes, string? imageContentType, CancellationToken cancellationToken)
        {
            Check(imageBytes is null, "test never captures a screen");
            var completion = new TaskCompletionSource<CoachAnswer>(TaskCreationOptions.RunContinuationsAsynchronously);
            _requests.Add(completion);
            return completion.Task; // Deliberately ignores cancellation to simulate a late provider reply.
        }
        internal void Reply(int index, string text) => _requests[index].SetResult(new(text, null));
        internal void Fail(int index) => _requests[index].SetException(new CoachRequestException("Simulated connection failure"));
    }
}
