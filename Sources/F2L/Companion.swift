import AppKit
import CoachCore

/// A borderless panel for resting Pip, the input bar and the reply card.
/// It never activates F2L, so the app being taught stays the frontmost app while you type.
class CompanionPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 172, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        title = "F2L · Pip"
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Resting Pip: click to open the conversation, drag to move.
final class PipHost: FlippedView {
    let pip = PipView(frame: .zero)
    var onClick: (() -> Void)?
    var onDrag: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var dragStart: NSPoint?
    var windowStart: NSPoint = .zero
    var dragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(pip)
        toolTip = "Ask Pip · drag to move"
        setAccessibilityRole(.button)
        setAccessibilityLabel("Ask Pip")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        pip.frame = bounds
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !dragging, abs(dx) < 4, abs(dy) < 4 { return }
        dragging = true
        window.setFrameOrigin(NSPoint(x: windowStart.x + dx, y: windowStart.y + dy))
        onDrag?()
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if dragging { onDragEnded?() } else { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

/// The input bar's background: dragging it moves the bar anywhere on screen; clicks on the text box and buttons
/// still go to them.
final class DragArea: FlippedView {
    var onMoved: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        onMoved?()
    }
}

/// Everything the Windows MainWindow does, on the Mac: resting Pip, the input bar at the bottom centre, Pip's reply
/// card, screen sharing, Excel selection, highlights and the teaching companion. Behaviour and wording follow
/// MainWindow.xaml.cs. Pip is silent: replies are shown, not spoken.
///
/// This file holds the state, layout, the input bar, a question's round trip, dictation and saving. The rest is split
/// by job: CompanionPointing.swift (circling places), CompanionLesson.swift (steps that finish by themselves) and
/// CompanionMenu.swift (the ··· menu, Settings and the profile window).
@MainActor
final class CompanionController: NSObject {
    static let greeting = "How can I help you?"
    static let askPlaceholder = "Ask Pip anything…"

    let window = CompanionPanel()
    let stage = FlippedView()
    let inputWindow = CompanionPanel()
    let bubble = ReplyBubble()
    let selectionReader = ExcelSelectionReader()
    var selectionBusy = false
    var selectionEnabled = false
    var lastSelectionRead = Date.distantPast
    let inputBar = RoundedBox(fill: Palette.panel, radius: 24, border: Palette.panelBorder)
    let inputArea = DragArea()
    /// The learner dragged the input bar: it stays where they put it (growing upwards) until "Put input back".
    var inputMoved = false
    /// The bar moved to the top by itself because it covered the place Pip is pointing at.
    var inputDodging = false
    /// Dictation adds to what was already typed instead of replacing it.
    var dictationPrefix = "", lastTranscript = "", consumedTranscript = 0, applyingTranscript = false
    let composerScroll: NSScrollView
    let composer: ComposerTextView
    let micButton = FlatButton("◉", size: 15, fill: nil)
    let sendButton = FlatButton("↑", size: 19, ink: .white, fill: Palette.send)
    let companionPanel = FlippedView()
    let pipHost = PipHost(frame: .zero)
    let moreButton = FlatButton("···", size: 12, fill: Palette.hex(0xF5F5F8))
    let menu = NSMenu()

    let coach: CoachClient
    var session = ConversationSession()
    var store: ConversationStore
    let capture = ScreenCaptureService()
    let excel = ExcelTargetResolver()
    let dictation = DictationInput()
    let testing: Bool
    var settingsWindow: SettingsWindow?
    let profileStore = ProfileStore()
    /// Read once at launch and again when the setup window closes, not on every question.
    lazy var profileDocument: ProfileDocument = testing ? ProfileDocument() : profileStore.load()
    var personalizeWindow: PersonalizeWindow?
    var intro: IntroWindow?

    var turn = 0, dictationSession = 0, highlightVersion = 0
    var turnTask: Task<Void, Never>?
    var pendingReply: ConversationEntry?
    var isListening = false, finishingDictation = false, screenSharingEnabled = true
    var panelOpen = false, leftAnchor = false, userPositioned = false, closed = false
    /// Pip stays in its corner and only the circle shows the place; "Pip walks to what it’s teaching" in Settings turns walking on.
    var followTargets = false
    var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var questionIntent = QuestionIntent.quickFact
    var pipSize = CGSize(width: 144, height: 164)
    var saveDraftTimer: Timer?
    var watchTimer: Timer?
    var waveTimer: Timer?
    var guide: GuideOverlayWindow?
    var teachingPip: TeachingCompanionWindow?
    var targetCapture: CapturedScreen?
    var targetCell: CellReference?
    var targetSheet: String?
    var checkingHighlight = false
    var targetShown = Date.distantPast
    var lastTargetBounds: CGRect?
    /// While a place is circled, the mouse button is checked 20 times a second so clicking the place moves the lesson on.
    var clickTimer: Timer?
    var clickWatch = ClickWatch()
    /// During a typing step, the focused box is checked twice a second (only its length and a hash, never the text).
    var typingWatch = TypingWatch()
    var lessonTicks = 0, readingTyping = false
    /// Whether the step's goal (an app or site in front) was already reached when the step appeared.
    var goalAtStart: Bool?
    /// Where the current reply and each lesson step happen, read from the screenshot taken with the question.
    /// Only the window's geometry is kept, never the picture.
    var replyCapture: CapturedScreen?
    var replyTarget: ScreenTarget?
    var stepTargets: [ScreenTarget?] = []
    var requestedCells: [CellReference] = []
    /// The question and steps of the current lesson, and the fresh look at the screen for the step being shown.
    var lessonGoal = "", lessonSteps: [String] = []
    var stepGuideTask: Task<Void, Never>?
    /// Step 1 is shown right after the question's own picture; every later showing of a step takes a new one.
    var firstStepSeen = false
    /// The recipes sent with the current question. Their on-screen names are checked against the screen before Pip
    /// points at one, so a renamed or missing button shows the recipe's own advice instead of a circle round a guess.
    var turnRecipes: [Recipe] = []
    var targetPersistent = false
    var shownAccessibilityTip = false

    var isRequestPending: Bool { pendingReply?.status == "pending" }

    init(coach: CoachClient = CoachClient(), store: ConversationStore = .fresh(), testing: Bool = false) {
        self.coach = coach
        self.store = store
        self.testing = testing
        (composerScroll, composer) = ComposerTextView.make()
        super.init()
        screenSharingEnabled = !testing
        buildViews()
        bubble.reducedMotion = reducedMotion
        bubble.onPage = { [weak self] in self?.clearHighlight() }
        bubble.onFocus = { [weak self] focus in
            guard let self else { return }
            switch focus {
            case .reply: point(at: replyTarget, checkRequest: true)
            case .step(let number): guideStep(number)
            case .nothing: break
            }
            // Each page starts fresh: clicks on its circle and typing in its box are watched while it is shown.
            if focus != .nothing { typingWatch = TypingWatch(); goalAtStart = nil; watchClicks() }
        }
        bubble.onAsk = { [weak self] question in self?.submit(question) }
        bubble.onCelebrate = { [weak self] in self?.wave() }
        bubble.onAskSomethingElse = { [weak self] in self?.openConversation() }
        // Back at rest, Pip's resting face returns, with its playful moves (wink, dance, stretch, peekaboo).
        bubble.onDismiss = { [weak self] in self?.pipHost.pip.setIntent(.quickFact) }
        composer.placeholder = Self.askPlaceholder
        composer.onSend = { [unowned self] in composerSend() }
        composer.onTextChange = { [unowned self] in draftChanged() }
        dictation.onTranscript = { [unowned self] text in
            guard isListening, !closed else { return }
            lastTranscript = text
            applyTranscript(text)
        }
        dictation.onFailure = { [unowned self] error in
            guard !closed, isListening else { return }
            stopDictation()
            setBusy(false)
            say("I couldn’t hear you (\(error)). You can type instead.")
        }
        pipHost.pip.setReducedMotion(reducedMotion)
        layoutCompanion()
        if !testing {
            capture.startTracking()
            let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.watchTarget(); self?.watchSelection() } }
            RunLoop.main.add(timer, forMode: .common)
            watchTimer = timer
        }
    }

    /// On launch: the opening plays, then Pip settles in its corner, waves and asks how it can help.
    func show(withIntro: Bool = false) {
        guard withIntro, intro == nil else { appear(); return }
        let intro = IntroWindow(home: homeRect, reducedMotion: reducedMotion)
        self.intro = intro
        intro.play { [weak self] in
            guard let self else { return }
            self.intro = nil
            appear()
            wave(for: 2.4)
            greet()
            // A missing profile is asked for every launch until the learner fills it in or says no profile is needed.
            if !testing && profileDocument.needsProfile { showProfile() }
        }
    }

    func appear() {
        window.orderFrontRegardless()
        pipHost.pip.windowDidShow()
        openConversation()
    }

    // MARK: - Views

    func buildViews() {
        window.contentView = stage
        stage.wantsLayer = true
        inputWindow.contentView = inputArea
        inputArea.addSubview(inputBar)
        inputBar.autoresizingMask = [.width, .height]
        inputArea.toolTip = "Drag to move"
        inputArea.onMoved = { [unowned self] in
            inputMoved = true
            inputDodging = false
            positionBubble()
        }
        inputWindow.level = .statusBar
        inputBar.shadow = {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.shadowColor = Palette.hex(0x20212C, alpha: 0.16)
            return shadow
        }()
        micButton.padding = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        micButton.toolTip = "Speak your question"
        micButton.setAccessibilityLabel("Speak your question")
        micButton.onClick = { [unowned self] in talk() }
        sendButton.padding = NSEdgeInsets(top: 0, left: 0, bottom: 2, right: 0)
        sendButton.cornerRadius = 17
        sendButton.toolTip = "Send · Enter"
        sendButton.setAccessibilityLabel("Send question")
        sendButton.onClick = { [unowned self] in sendClicked() }
        [composerScroll, micButton, sendButton].forEach(inputBar.addSubview)

        pipHost.onClick = { [unowned self] in openConversation() }
        pipHost.onDrag = { [weak self] in self?.positionBubble() }
        pipHost.onDragEnded = { [unowned self] in pipDragEnded() }
        moreButton.padding = NSEdgeInsets(top: 0, left: 0, bottom: 2, right: 0)
        moreButton.toolTip = "Pip controls"
        moreButton.onClick = { [unowned self] in popUpMenu(from: moreButton) }
        [pipHost, moreButton].forEach(companionPanel.addSubview)
        stage.addSubview(companionPanel)
    }

    // MARK: - Layout (mirrors MainWindow.LayoutCompanion)

    /// The window frame in global top-left coordinates.
    var frameTL: CGRect {
        get { ScreenSpace.toTopLeft(window.frame) }
        set { window.setFrame(ScreenSpace.toAppKit(newValue), display: true) }
    }

    var workArea: CGRect {
        let center = CGPoint(x: frameTL.minX + companionPanel.frame.midX, y: frameTL.minY + companionPanel.frame.minY + pipSize.height / 2)
        return ScreenSpace.workArea(at: center)
    }

    /// Resting Pip on screen, global top-left.
    var homeRect: CGRect {
        CGRect(x: frameTL.minX + companionPanel.frame.minX + pipHost.frame.minX, y: frameTL.minY + companionPanel.frame.minY,
               width: pipSize.width, height: pipSize.height)
    }

    func layoutCompanion() {
        let oldCenter = CGPoint(x: frameTL.minX + companionPanel.frame.midX, y: frameTL.minY + companionPanel.frame.minY + pipSize.height / 2)
        let work = workArea
        let companionWidth = pipSize.width + 14
        let width = companionWidth + 12
        let height = pipSize.height + 36
        companionPanel.frame = NSRect(x: 6, y: 4, width: companionWidth, height: pipSize.height + 24)
        let w = companionPanel.frame.width
        pipHost.frame = NSRect(x: (w - pipSize.width) / 2, y: 0, width: pipSize.width, height: pipSize.height)
        moreButton.frame = NSRect(x: (w - 29) / 2, y: pipSize.height - 2, width: 29, height: 24)
        layoutInputBar()
        var frame = CGRect(x: 0, y: 0, width: width, height: height)
        if userPositioned {
            frame.origin = CGPoint(x: oldCenter.x - companionPanel.frame.midX, y: oldCenter.y - (companionPanel.frame.minY + pipSize.height / 2))
        } else {
            frame.origin = CGPoint(x: leftAnchor ? work.minX + 12 : work.maxX - width - 12, y: work.maxY - height - 12)
        }
        frameTL = clamped(frame, in: work)
        positionBubble()
    }

    func clamped(_ frame: CGRect, in area: CGRect) -> CGRect {
        var f = frame
        f.origin.x = min(max(f.minX, area.minX), max(area.minX, area.maxX - f.width))
        f.origin.y = min(max(f.minY, area.minY), max(area.minY, area.maxY - f.height))
        return f
    }

    func clampPosition() { frameTL = clamped(frameTL, in: workArea) }
    func moveWindow(dy: CGFloat) { var f = frameTL; f.origin.y += dy; frameTL = f }

    /// One rounded bar at the bottom centre: the text, the microphone and Send. Nothing else.
    func layoutInputBar() {
        let work = workArea
        let w = min(620, work.width - 32)
        let textHeight = min(92, max(22, ceil(composer.contentHeight)))
        let h = textHeight + 30
        let current = ScreenSpace.toTopLeft(inputWindow.frame)
        let frame: CGRect
        if inputMoved, current.width > 0 {
            frame = clamped(CGRect(x: current.minX, y: current.maxY - h, width: w, height: h), in: ScreenSpace.workArea(at: CGPoint(x: current.midX, y: current.midY)))
        } else if inputDodging {
            frame = CGRect(x: work.midX - w / 2, y: work.minY + 18, width: w, height: h)
        } else {
            frame = CGRect(x: work.midX - w / 2, y: work.maxY - h - 18, width: w, height: h)
        }
        inputWindow.setFrame(ScreenSpace.toAppKit(frame), display: true)
        inputBar.frame = inputArea.bounds
        composerScroll.frame = NSRect(x: 22, y: 15, width: w - 22 - 94, height: textHeight)
        composer.frame.size.width = composerScroll.contentSize.width
        micButton.frame = NSRect(x: w - 90, y: (h - 34) / 2, width: 34, height: 34)
        sendButton.frame = NSRect(x: w - 50, y: (h - 34) / 2, width: 34, height: 34)
    }

    func positionBubble() {
        bubble.follow(teachingPip?.screenBounds ?? homeRect, avoiding: lastTargetBounds.map { TargetSnap.circle(around: $0).insetBy(dx: -12, dy: -12) },
                      input: panelRect)
    }

    func pipDragEnded() {
        userPositioned = true
        clampPosition()
        positionBubble()
        let center = frameTL.minX + companionPanel.frame.midX
        let anchor = center < workArea.midX
        if anchor != leftAnchor { leftAnchor = anchor; layoutCompanion() }
    }

    // MARK: - Opening and closing

    func openConversation() {
        capture.rememberForeground()
        // Opening/focusing a view must never cancel a turn or replace its messages.
        panelOpen = true
        layoutCompanion()
        bubble.resume()
        inputWindow.orderFrontRegardless()
        if !testing { inputWindow.makeKey() } // the render check must never take the keyboard
        inputWindow.makeFirstResponder(composer)
        if let target = lastTargetBounds { updateTeachingCompanion(target) }
    }

    func minimiseConversation() {
        panelOpen = false
        stopTeachingCompanion()
        inputWindow.orderOut(nil)
        bubble.orderOut(nil)
        layoutCompanion()
    }

    // MARK: - Composer

    func draftChanged() {
        // Typing while dictating keeps what was typed; later speech is added after it.
        if isListening, !applyingTranscript {
            dictationPrefix = composer.string
            consumedTranscript = lastTranscript.count
        }
        layoutInputBar()
        saveDraftTimer?.invalidate()
        let timer = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.saveConversation() } }
        RunLoop.main.add(timer, forMode: .common)
        saveDraftTimer = timer
    }

    func composerSend() {
        if isRequestPending { return } // Send turns into Stop while Pip is thinking
        submit(composer.string)
    }

    func sendClicked() {
        if isRequestPending {
            cancelCurrentTurn()
            say("Stopped. Ask me again when you’re ready.")
        } else {
            submit(composer.string)
        }
    }

    func setComposer(_ text: String) {
        composer.string = text
        composer.didChangeText()
    }

    func setPlaceholder(_ text: String) {
        composer.placeholder = text
        composer.needsDisplay = true
    }

    /// Pip says a short line in its card: a greeting, a problem, or what it is doing.
    /// Notices and problems come with Pip's curious emote; pass another for greetings and progress.
    func say(_ line: String, emote: PipEmote = .curious, choices: [ReplyBubble.Choice] = []) {
        bubble.say(line, emote: emote, choices: choices)
        positionBubble()
    }

    /// "How can I help you, Alex?" with what they chose to learn, to pick from. Nothing starts until they choose.
    func greet(_ saved: ProfileDocument? = nil) {
        let document = saved ?? profileDocument
        if document.needsProfile && !testing {
            say("I don't know about your work yet. Tell me a little, so my help fits what you do.", emote: .hello,
                choices: [("Set up my profile", true, { [weak self] in self?.showProfile() }),
                          ("No profile needed", false, { [weak self] in self?.declineProfile() })])
            return
        }
        guard let profile = document.profile, profile.personalizationEnabled else { say(Self.greeting, emote: .hello); return }
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let topics = Array(profile.learning.prefix(3))
        if topics.isEmpty {
            say(name.isEmpty ? Self.greeting : "How can I help you, \(name)?", emote: .hello,
                choices: [("Choose what to learn", true, { [weak self] in self?.showProfile() })])
        } else {
            say(name.isEmpty ? "What would you like to learn today?" : "What would you like to learn today, \(name)?", emote: .hello,
                choices: topics.map { topic in (topic, true, { [weak self] in self?.submit(LearnerProfile.lessonQuestion(topic)) }) }
                    + [("Change what I learn", false, { [weak self] in self?.showProfile() })])
        }
    }

    /// "No profile needed": Pip stops asking until the learner sets one up from the menu.
    func declineProfile() {
        var document = profileStore.load()
        document.noProfileWanted = true
        document.onboardingComplete = true
        try? profileStore.save(document)
        profileDocument = document
        personalizeWindow?.close()
        say(Self.greeting, emote: .hello)
    }

    func wave(for seconds: TimeInterval = 1.6) {
        waveTimer?.invalidate()
        pipHost.pip.setWaving(true)
        teachingPip?.pip.setWaving(true)
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pipHost.pip.setWaving(false)
                self?.teachingPip?.pip.setWaving(false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        waveTimer = timer
    }

    // MARK: - A conversation turn (mirrors MainWindow.SubmitAsync)

    func submit(_ question: String) {
        if isListening || finishingDictation { say("Tap ■ to finish speaking first."); return }
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        // Choose the app before anything else so the whole turn uses the same identity.
        let app = screenSharingEnabled ? capture.target() : nil
        selectionEnabled = false
        bubble.updateSelection(nil, line: "")
        cancelCurrentTurn()
        clearHighlight()
        forgetPlaces()
        turn += 1
        let myTurn = turn
        let entry = session.begin(clean)
        pendingReply = entry
        say(ConversationSession.pendingText, emote: .thinking)
        setComposer("")
        openConversation()
        setBusy(true)
        saveConversation()
        let intent = QuestionIntent.classify(clean)
        questionIntent = intent
        pipHost.pip.setIntent(intent)
        turnTask = Task { [weak self] in
            await self?.runTurn(entry, question: clean, app: app, turn: myTurn)
        }
    }

    /// The names of buttons, tabs and text in the shared window (Accessibility, then the screen read on this Mac), so
    /// the AI names places that really exist there and F2L can find them exactly. Empty without a picture.
    func screenNames(_ captured: CapturedScreen?) async -> [String] {
        guard let captured, !captured.jpeg.isEmpty else { return [] }
        let jpeg = captured.jpeg, frame = captured.frame, pid = captured.app.pid, trusted = DesktopAccessibility.isTrusted
        // Both at once, and the control walk kept short: this runs before the question is sent.
        async let controls = Task.detached(priority: .userInitiated) {
            trusted ? DesktopAccessibility.controls(pid: pid, in: frame, limit: 2500, budget: 0.6).map(\.name) : []
        }.value
        async let read = Task.detached(priority: .userInitiated) {
            ScreenReading.lines(jpeg: jpeg, frame: frame).map { $0.map(\.text).joined(separator: " ") }
        }.value
        return await controls + read
    }

    func runTurn(_ entry: ConversationEntry, question: String, app: ForegroundApp?, turn myTurn: Int) async {
        var captured: CapturedScreen?
        var screenUnavailable: String?
        // How long each part of the turn took, written to pointing.log ("kind": "turn") to find what makes Pip slow.
        let began = Date()
        var timing: [String: Any] = ["kind": "turn", "provider": coach.provider.name, "app": app?.name ?? ""]
        func mark(_ name: String, since start: Date) { timing[name] = (Date().timeIntervalSince(start) * 100).rounded() / 100 }
        var waiting: Task<Void, Never>?
        defer {
            waiting?.cancel()
            mark("totalSeconds", since: began)
            timing["outcome"] = timing["outcome"] ?? (myTurn == turn ? "error-or-cancelled" : "superseded")
            PointingDiagnostics.record(timing)
            captured?.jpeg.resetBytes(in: 0..<(captured?.jpeg.count ?? 0))
            if myTurn == turn, !closed {
                pendingReply = nil
                turnTask = nil
                setBusy(false)
                saveConversation()
            }
        }
        do {
            let cells = CellReference.find(question)
            let directCellRequest = cells.count == 1 && CellReference.isPointingOnly(question)
            if !coach.isConfigured && !directCellRequest { throw CoachRequestError(coach.notConfigured) }
            if screenSharingEnabled {
                do {
                    // A cell-pointing request only needs to know which window Excel is in; no picture is taken.
                    let start = Date()
                    captured = directCellRequest ? try capture.locate(app) : try await capture.capture(app)
                    mark("captureSeconds", since: start)
                } catch let error as ScreenCaptureError {
                    screenUnavailable = error.message
                    timing["capture"] = "unavailable"
                }
            }
            guard myTurn == turn else { return }
            var context: ExcelContext?
            if screenSharingEnabled, app?.isExcel == true {
                let result = await selectionReader.read(ask: true)
                guard myTurn == turn else { return }
                if screenSharingEnabled {
                    context = result.context
                    selectionEnabled = !result.message.contains("Privacy & Security")
                    bubble.updateSelection(result.context, line: result.message)
                }
            } else { selectionEnabled = false; bubble.updateSelection(nil, line: "") }
            let answer: CoachAnswer
            var exact: ExcelTargetResult?
            var exactCell: CellReference?
            if directCellRequest {
                let cell = cells[0]
                exactCell = cell
                let result = if let captured { await excel.resolve(captured, cell) } else {
                    ExcelTargetResult(message: screenUnavailable ?? "Screen sharing is paused. Turn it on in Pip's menu so I can verify the cell.")
                }
                exact = result
                // Without Excel's confirmation (always on Mac) Pip still finds the cell by reading the screen.
                let findOnScreen = !result.verified && captured != nil
                answer = CoachAnswer(reply: result.verified || findOnScreen ? "Select \(cell.address): column \(cell.columnLetters), row \(cell.row)." : result.message,
                                     target: findOnScreen ? ScreenTarget(left: 0, top: 0, right: 0, bottom: 0, label: cell.address, cell: cell.address) : nil)
            } else {
                var start = Date()
                let names = await screenNames(captured)
                mark("screenNamesSeconds", since: start)
                guard myTurn == turn else { return }
                // The front window's title says which page is open, so a bare "Copilot" question resolves to the
                // product the learner is actually looking at.
                let title = captured.map { ScreenCaptureService.windowTitle(of: $0.app.pid) }
                // The same selection the question carries, kept so pointing can check the recipe's names on screen.
                turnRecipes = CoachClient.reference(question: question, profile: profileDocument.profile,
                                                    app: captured?.app.name, windowTitle: title,
                                                    library: .shared, recipes: .shared).recipes
                start = Date()
                // Say so when the AI is slow, instead of a "Thinking…" that looks stuck.
                let providerName = coach.provider.name
                waiting = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled, let self, myTurn == self.turn, self.pendingReply === entry else { return }
                    self.say("Still waiting for \(providerName). It's answering slowly right now; I'll show the reply as soon as it arrives.", emote: .thinking)
                }
                answer = try await coach.answer(question: CoachClient.compose(question: question, platform: "macOS", excel: context,
                    profile: profileDocument.profile, app: captured?.app.name, windowTitle: title, screenNames: names,
                    library: .shared, recipes: .shared), history: session.providerHistory(excluding: entry.turnID), jpeg: captured?.jpeg)
                waiting?.cancel()
                mark("aiSeconds", since: start)
                timing["steps"] = answer.steps.count
            }
            try Task.checkCancellation()
            guard myTurn == turn else { return }
            timing["outcome"] = "answered"
            entry.text = answer.text
            entry.status = "complete"
            pendingReply = nil
            setBusy(false)
            // Remember where the reply and each step happen; showing a page sends Pip there.
            replyCapture = captured.map { CapturedScreen(jpeg: Data(), windowID: $0.windowID, frame: $0.frame, app: $0.app) }
            // A step or reply the AI left without a place still points at what it names.
            replyTarget = answer.placeForReply
            stepTargets = answer.placesForSteps
            lessonGoal = question
            lessonSteps = answer.steps
            firstStepSeen = false
            requestedCells = cells
            bubble.show(reply: answer.reply, steps: answer.steps)
            positionBubble()
            if let exact, exact.verified, let bounds = exact.bounds, let captured, let exactCell {
                showTarget(captured, bounds, verified: true, cell: exactCell, sheet: exact.sheet)
            }
            saveConversation()
        } catch is CancellationError {
            session.stop(entry)
        } catch {
            guard myTurn == turn, !closed else { return }
            entry.text = (error as? CoachRequestError)?.message ?? (error as? ScreenCaptureError)?.message
                ?? "I couldn't finish that request. Please try again."
            timing["outcome"] = "error: \(error)"
            entry.status = "error"
            say(entry.text)
        }
    }

    func cancelCurrentTurn() {
        turn += 1
        turnTask?.cancel()
        turnTask = nil
        session.stop(pendingReply)
        pendingReply = nil
        stopDictation()
        setBusy(false)
        saveConversation()
    }

    func setBusy(_ busy: Bool) {
        pipHost.pip.setThinking(busy)
        sendButton.title = busy ? "■" : "↑"
        sendButton.textSize = busy ? 14 : 19
        sendButton.toolTip = busy ? "Stop" : "Send · Enter"
        sendButton.isEnabled = !isListening && !finishingDictation
        micButton.isEnabled = !finishingDictation
    }

    func newChat() {
        cancelCurrentTurn()
        saveDraftTimer?.invalidate()
        clearHighlight()
        selectionEnabled = false
        session = ConversationSession()
        forgetPlaces()
        store = store.nextSession()
        setComposer("")
        bubble.dismiss()
        bubble.updateSelection(nil, line: "")
        openConversation()
        greet()
    }

    // MARK: - Dictation (mirrors Talk_Click)

    func talk() {
        guard !finishingDictation else { return }
        if !isListening {
            cancelCurrentTurn()
            let request = dictationSession
            Task {
                let problem = await dictation.prepare()
                guard request == dictationSession, !closed else { return }
                if let problem { say("The microphone isn’t available: \(problem)"); return }
                do { try dictation.start() } catch {
                    say("The microphone isn’t available: \(error.localizedDescription)")
                    return
                }
                dictationSession += 1
                isListening = true
                dictationPrefix = composer.string
                lastTranscript = ""
                consumedTranscript = 0
                pipHost.pip.setListening(true)
                micButton.title = "■"
                micButton.toolTip = "Finish speaking"
                setPlaceholder("Listening… tap ■ when you’re done")
                setBusy(false)
            }
            return
        }
        let mySession = dictationSession
        isListening = false
        finishingDictation = true
        pipHost.pip.setListening(false)
        setBusy(false)
        Task {
            let final = await dictation.stop()
            guard mySession == dictationSession, !closed else { return }
            // The recogniser can end with nothing even after showing words; never lose what was already in the box.
            applyTranscript(final.isEmpty ? lastTranscript : final)
            setPlaceholder(composer.string.isEmpty ? "I didn’t catch that. Try again or type." : Self.askPlaceholder)
            inputWindow.makeFirstResponder(composer)
            finishingDictation = false
            micButton.title = "◉"
            micButton.toolTip = "Speak your question"
            setBusy(false)
        }
    }

    /// What was typed before (or during) dictation, then the words spoken since.
    func applyTranscript(_ transcript: String) {
        let spoken = String(transcript.dropFirst(consumedTranscript)).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = dictationPrefix
        let joined = prefix.isEmpty || spoken.isEmpty ? prefix + spoken
            : prefix + (prefix.last?.isWhitespace == true ? "" : " ") + spoken
        guard composer.string != joined else { return }
        applyingTranscript = true
        setComposer(joined)
        applyingTranscript = false
    }

    func stopDictation() {
        dictationSession += 1
        if isListening || finishingDictation { dictation.cancel() }
        isListening = false
        finishingDictation = false
        pipHost.pip.setListening(false)
        micButton.title = "◉"
        setPlaceholder(Self.askPlaceholder)
    }

    // MARK: - Saving and quitting

    func saveConversation() {
        if !store.save(session, draft: composer.string) { Log.app.error("Couldn't save the conversation") }
    }

    func shutdown() {
        guard !closed else { return }
        cancelCurrentTurn()
        closed = true
        intro?.finish()
        personalizeWindow?.close()
        saveDraftTimer?.invalidate()
        watchTimer?.invalidate()
        waveTimer?.invalidate()
        clearHighlight()
        dictation.cancel()
        capture.stopTracking()
        saveConversation()
        bubble.dismiss()
        inputWindow.orderOut(nil)
    }

    // MARK: - Test hooks

    /// Adds a finished sample reply (used by --render), without touching the network.
    func seedSample(question: String, reply: String, steps: [String] = []) {
        let entry = session.begin(question)
        entry.text = CoachAnswer(reply: reply, steps: steps, target: nil).text
        entry.status = "complete"
        bubble.show(reply: reply, steps: steps)
        positionBubble()
    }

    func simulateTarget(_ target: CGRect) {
        followTargets = true // the render check draws the walking Pip too
        lastTargetBounds = target
        if guide == nil { guide = GuideOverlayWindow() }
        guide?.show(target, verified: false)
        watchClicks() // so the soak check measures the click watch too
        updateTeachingCompanion(target)
    }

    func sampleGreeting() { greet() }
    func samplePersonalGreeting() {
        var profile = LearnerProfile()
        profile.name = "Alex"; profile.role = "Operations coordinator"; profile.goal = "Make weekly reporting easier"
        profile.learning = ["Pivot tables", "Charts for reports"]
        greet(ProfileDocument(profile: profile, plan: StarterPlan.draft(for: profile), onboardingComplete: true))
    }
    func revealSample() { bubble.finishReveal() }
    func sampleStep() { bubble.sampleStep(selection: "Excel has selected A1:A4 · Budget", areas: ["A1:A4"]) }
    func makeIntro(reducedMotion: Bool = false) -> IntroWindow { IntroWindow(home: homeRect, reducedMotion: reducedMotion) }
    var inputIsCentred: Bool { abs(ScreenSpace.toTopLeft(inputWindow.frame).midX - workArea.midX) < 1 }
    var contentView: NSView { stage }
    var replyView: NSView? { bubble.contentView }
    var inputView: NSView? { inputWindow.contentView }
    var teachingWindow: NSWindow? { teachingPip }
    var guideView: NSView? { guide?.contentView }
}
