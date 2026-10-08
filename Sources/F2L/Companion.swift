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
private final class PipHost: FlippedView {
    let pip = PipView(frame: .zero)
    var onClick: (() -> Void)?
    var onDrag: (() -> Void)?
    var onDragEnded: (() -> Void)?
    private var dragStart: NSPoint?
    private var windowStart: NSPoint = .zero
    private var dragging = false

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

/// "AI provider" in Pip's menu: one item per provider, the current one ticked, providers without a key marked.
/// Choosing one writes "Provider" into local.settings.json; the next question uses it.
private final class ProviderMenu: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = LocalSettings.provider()
        for provider in Provider.allCases {
            let hasKey = !LocalSettings.read(provider.key).isEmpty
            let item = MenuAction.item(provider.name + (hasKey ? "" : " · add a key in Settings"), checked: provider == current) { _ in
                LocalSettings.setProvider(provider)
            }
            menu.addItem(item)
        }
    }
}

/// The input bar's background: dragging it moves the bar anywhere on screen; clicks on the text box and buttons
/// still go to them.
private final class DragArea: FlippedView {
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
@MainActor
final class CompanionController: NSObject {
    static let greeting = "How can I help you?"
    static let askPlaceholder = "Ask Pip anything…"

    let window = CompanionPanel()
    private let stage = FlippedView()
    private let inputWindow = CompanionPanel()
    private let bubble = ReplyBubble()
    private let selectionReader = ExcelSelectionReader()
    private var selectionBusy = false
    private var selectionEnabled = false
    private var lastSelectionRead = Date.distantPast
    private let inputBar = RoundedBox(fill: Palette.panel, radius: 24, border: Palette.panelBorder)
    private let inputArea = DragArea()
    /// The learner dragged the input bar: it stays where they put it (growing upwards) until "Put input back".
    private var inputMoved = false
    /// The bar moved to the top by itself because it covered the place Pip is pointing at.
    private var inputDodging = false
    /// Dictation adds to what was already typed instead of replacing it.
    private var dictationPrefix = "", lastTranscript = "", consumedTranscript = 0, applyingTranscript = false
    private let composerScroll: NSScrollView
    private let composer: ComposerTextView
    private let micButton = FlatButton("◉", size: 15, fill: nil)
    private let sendButton = FlatButton("↑", size: 19, ink: .white, fill: Palette.send)
    private let companionPanel = FlippedView()
    private let pipHost = PipHost(frame: .zero)
    private let moreButton = FlatButton("···", size: 12, fill: Palette.hex(0xF5F5F8))
    private let menu = NSMenu()
    private let providerMenu = ProviderMenu()
    private var sizeItems: [NSMenuItem] = []

    private let coach: CoachClient
    private var session = ConversationSession()
    private var store: ConversationStore
    private let capture = ScreenCaptureService()
    private let excel = ExcelTargetResolver()
    private let dictation = DictationInput()
    private let testing: Bool
    private var settingsWindow: NSWindow?
    private var intro: IntroWindow?

    private var turn = 0, dictationSession = 0, highlightVersion = 0
    private var turnTask: Task<Void, Never>?
    private var pendingReply: ConversationEntry?
    private var isListening = false, finishingDictation = false, screenSharingEnabled = true
    private var panelOpen = false, leftAnchor = false, userPositioned = false, closed = false
    /// Pip stays in its corner and only the circle shows the place; "Pip follows teaching targets" turns walking on.
    private var followTargets = false
    private var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var questionIntent = QuestionIntent.quickFact
    private var pipSize = CGSize(width: 144, height: 164)
    private var saveDraftTimer: Timer?
    private var watchTimer: Timer?
    private var waveTimer: Timer?
    private var guide: GuideOverlayWindow?
    private var teachingPip: TeachingCompanionWindow?
    private var targetCapture: CapturedScreen?
    private var targetCell: CellReference?
    private var targetSheet: String?
    private var checkingHighlight = false
    private var targetShown = Date.distantPast
    private var lastTargetBounds: CGRect?
    /// Where the current reply and each lesson step happen, read from the screenshot taken with the question.
    /// Only the window's geometry is kept, never the picture.
    private var replyCapture: CapturedScreen?
    private var replyTarget: ScreenTarget?
    private var stepTargets: [ScreenTarget?] = []
    private var requestedCells: [CellReference] = []
    private var targetPersistent = false
    private var shownAccessibilityTip = false

    var isRequestPending: Bool { pendingReply?.status == "pending" }

    init(coach: CoachClient = CoachClient(), store: ConversationStore = .fresh(), testing: Bool = false) {
        self.coach = coach
        self.store = store
        self.testing = testing
        (composerScroll, composer) = ComposerTextView.make()
        super.init()
        screenSharingEnabled = !testing
        buildViews()
        buildMenu()
        bubble.reducedMotion = reducedMotion
        bubble.onPage = { [weak self] in self?.clearHighlight() }
        bubble.onFocus = { [weak self] focus in
            guard let self else { return }
            switch focus {
            case .reply: point(at: replyTarget, checkRequest: true)
            case .step(let number): point(at: stepTargets.indices.contains(number) ? stepTargets[number] : nil, checkRequest: false)
            case .nothing: break
            }
        }
        bubble.onAsk = { [weak self] question in self?.submit(question) }
        bubble.onCelebrate = { [weak self] in self?.wave() }
        bubble.onAskSomethingElse = { [weak self] in self?.openConversation() }
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
            say(Self.greeting)
        }
    }

    private func appear() {
        window.orderFrontRegardless()
        pipHost.pip.windowDidShow()
        openConversation()
    }

    // MARK: - Views

    private func buildViews() {
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

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.addItem(MenuAction.item("New chat") { [unowned self] _ in newChat() })
        menu.addItem(MenuAction.item("Hide input") { [unowned self] _ in minimiseConversation() })
        menu.addItem(MenuAction.item("Put input back at the bottom") { [unowned self] _ in inputMoved = false; layoutInputBar(); positionBubble() })
        menu.addItem(.separator())
        let providers = NSMenu()
        providers.delegate = providerMenu
        let providerItem = NSMenuItem(title: "AI provider", action: nil, keyEquivalent: "")
        providerItem.submenu = providers
        menu.addItem(providerItem)
        menu.addItem(MenuAction.item("Share active app window", checked: screenSharingEnabled) { [unowned self] item in
            screenSharingEnabled.toggle()
            item.state = screenSharingEnabled ? .on : .off
            if !screenSharingEnabled { clearHighlight(); selectionEnabled = false; bubble.updateSelection(nil, line: "") }
        })
        menu.addItem(MenuAction.item("Pip follows teaching targets", checked: false) { [unowned self] item in
            followTargets.toggle()
            item.state = followTargets ? .on : .off
            if followTargets, let target = lastTargetBounds { updateTeachingCompanion(target) } else { stopTeachingCompanion() }
        })
        menu.addItem(MenuAction.item("Reduce animation", checked: reducedMotion) { [unowned self] item in
            reducedMotion.toggle()
            bubble.reducedMotion = reducedMotion
            item.state = reducedMotion ? .on : .off
            pipHost.pip.setReducedMotion(reducedMotion)
            teachingPip?.reducedMotion = reducedMotion
            teachingPip?.pip.setReducedMotion(reducedMotion)
        })
        let sizes = NSMenu()
        for (title, size) in [("Small", CGSize(width: 112, height: 128)), ("Medium", CGSize(width: 144, height: 164)),
                              ("Large", CGSize(width: 180, height: 205))] {
            let item = MenuAction.item(title, checked: title == "Medium") { [unowned self] item in
                if userPositioned { moveWindow(dy: -(size.height - pipSize.height) / 2) }
                pipSize = size
                sizeItems.forEach { $0.state = $0 === item ? .on : .off }
                layoutCompanion()
            }
            sizeItems.append(item)
            sizes.addItem(item)
        }
        let sizeMenu = NSMenuItem(title: "Pip size", action: nil, keyEquivalent: "")
        sizeMenu.submenu = sizes
        menu.addItem(sizeMenu)
        menu.addItem(MenuAction.item("Clear screen highlight") { [unowned self] _ in clearHighlight() })
        menu.addItem(MenuAction.item("Move to other corner") { [unowned self] _ in leftAnchor.toggle(); userPositioned = false; layoutCompanion() })
        menu.addItem(MenuAction.item("Fix permissions…") { [unowned self] _ in fixPermissions() })
        menu.addItem(MenuAction.item("Save pointing diagnostics") { [unowned self] _ in saveDiagnostics() })
        menu.addItem(MenuAction.item("Settings…") { [unowned self] _ in showSettings() })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Quit F2L") { _ in NSApp.terminate(nil) })
    }

    private func popUpMenu(from button: NSView) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    // MARK: - Layout (mirrors MainWindow.LayoutCompanion)

    /// The window frame in global top-left coordinates.
    private var frameTL: CGRect {
        get { ScreenSpace.toTopLeft(window.frame) }
        set { window.setFrame(ScreenSpace.toAppKit(newValue), display: true) }
    }

    private var workArea: CGRect {
        let center = CGPoint(x: frameTL.minX + companionPanel.frame.midX, y: frameTL.minY + companionPanel.frame.minY + pipSize.height / 2)
        return ScreenSpace.workArea(at: center)
    }

    /// Resting Pip on screen, global top-left.
    private var homeRect: CGRect {
        CGRect(x: frameTL.minX + companionPanel.frame.minX + pipHost.frame.minX, y: frameTL.minY + companionPanel.frame.minY,
               width: pipSize.width, height: pipSize.height)
    }

    private func layoutCompanion() {
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

    private func clamped(_ frame: CGRect, in area: CGRect) -> CGRect {
        var f = frame
        f.origin.x = min(max(f.minX, area.minX), max(area.minX, area.maxX - f.width))
        f.origin.y = min(max(f.minY, area.minY), max(area.minY, area.maxY - f.height))
        return f
    }

    private func clampPosition() { frameTL = clamped(frameTL, in: workArea) }
    private func moveWindow(dy: CGFloat) { var f = frameTL; f.origin.y += dy; frameTL = f }

    /// One rounded bar at the bottom centre: the text, the microphone and Send. Nothing else.
    private func layoutInputBar() {
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

    private func positionBubble() {
        bubble.follow(teachingPip?.screenBounds ?? homeRect, avoiding: lastTargetBounds.map { TargetSnap.circle(around: $0).insetBy(dx: -12, dy: -12) },
                      input: panelRect)
    }

    private func pipDragEnded() {
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

    private func draftChanged() {
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

    private func composerSend() {
        if isRequestPending { return } // Send turns into Stop while Pip is thinking
        submit(composer.string)
    }

    private func sendClicked() {
        if isRequestPending {
            cancelCurrentTurn()
            say("Stopped. Ask me again when you’re ready.")
        } else {
            submit(composer.string)
        }
    }

    private func setComposer(_ text: String) {
        composer.string = text
        composer.didChangeText()
    }

    private func setPlaceholder(_ text: String) {
        composer.placeholder = text
        composer.needsDisplay = true
    }

    /// Pip says a short line in its card: a greeting, a problem, or what it is doing.
    private func say(_ line: String) {
        bubble.say(line)
        positionBubble()
    }

    private func wave(for seconds: TimeInterval = 1.6) {
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
        say(ConversationSession.pendingText)
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

    private func runTurn(_ entry: ConversationEntry, question: String, app: ForegroundApp?, turn myTurn: Int) async {
        var captured: CapturedScreen?
        var screenUnavailable: String?
        defer {
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
                    captured = directCellRequest ? try capture.locate(app) : try await capture.capture(app)
                } catch let error as ScreenCaptureError {
                    screenUnavailable = error.message
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
                answer = try await coach.answer(question: CoachClient.compose(question: question, platform: "macOS", excel: context), history: session.providerHistory(excluding: entry.turnID), jpeg: captured?.jpeg)
            }
            try Task.checkCancellation()
            guard myTurn == turn else { return }
            entry.text = answer.text
            entry.status = "complete"
            pendingReply = nil
            setBusy(false)
            // Remember where the reply and each step happen; showing a page sends Pip there.
            replyCapture = captured.map { CapturedScreen(jpeg: Data(), windowID: $0.windowID, frame: $0.frame, app: $0.app) }
            replyTarget = answer.target
            stepTargets = answer.stepTargets
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

    private func setBusy(_ busy: Bool) {
        pipHost.pip.setThinking(busy)
        sendButton.title = busy ? "■" : "↑"
        sendButton.textSize = busy ? 14 : 19
        sendButton.toolTip = busy ? "Stop" : "Send · Enter"
        sendButton.isEnabled = !isListening && !finishingDictation
        micButton.isEnabled = !finishingDictation
    }

    // MARK: - Highlights and the teaching companion

    private var panelRect: CGRect? {
        guard panelOpen, inputWindow.isVisible else { return nil }
        return ScreenSpace.toTopLeft(inputWindow.frame)
    }

    /// Sends Pip to where the reply or step happens and circles it, found on the screen as it is now:
    /// - the window is pictured again and its words are read on this Mac (Apple Vision), so a button or tab is circled
    ///   where its name appears, and an Excel cell where its column letter and row number meet;
    /// - Accessibility's named controls are used too, and Excel's own confirmation where it gives one (Windows).
    /// The model's rough position is shown dashed at once, and replaced by a checked place when one is found.
    /// Every decision is written to pointing.log for debugging.
    private func point(at target: ScreenTarget?, checkRequest: Bool) {
        guard let target, let captured = replyCapture, screenSharingEnabled else { return }
        let cell = target.cell.flatMap(CellReference.parse)
        // A direct "circle A1" can't be quietly answered with B1.
        if checkRequest, let cell, requestedCells.count == 1, !CellReference.matchesRequest(cell, requestedCells) { return }
        let version = highlightVersion
        let estimate = target.hasBox ? CompanionPlacement.fromScreenshot(window: captured.frame, target: target) : nil
        var log: [String: Any] = ["label": target.label, "cell": target.cell ?? "", "window": PointingDiagnostics.rect(captured.frame) ?? [:],
                                  "modelBox": PointingDiagnostics.rect(estimate) ?? [:], "app": captured.app.name]
        Task {
            defer { PointingDiagnostics.record(log) }
            if let cell {
                let result = await excel.resolve(captured, cell)
                guard version == highlightVersion, !closed else { log["source"] = "superseded"; return }
                if result.verified, let bounds = result.bounds {
                    log["source"] = "excel-verified"; log["drawn"] = PointingDiagnostics.rect(bounds)
                    showTarget(captured, bounds, verified: true, cell: cell, sheet: result.sheet, persistent: true)
                    return
                }
            }
            // Go straight to where the model saw it (dashed) while the screen is read; a checked place replaces it.
            if let estimate { showTarget(captured, estimate, verified: false, cell: nil, sheet: nil, persistent: true) }
            // Picture the window as it is now and read it; the picture is dropped straight after.
            var now = captured
            var lines: [[ScreenWord]] = []
            if let fresh = try? await capture.capture(captured.app), fresh.windowID == captured.windowID {
                let jpeg = fresh.jpeg, frame = fresh.frame
                lines = await Task.detached(operation: { ScreenReading.lines(jpeg: jpeg, frame: frame) }).value
                fresh.jpeg.resetBytes(in: 0..<fresh.jpeg.count)
                now = CapturedScreen(jpeg: Data(), windowID: fresh.windowID, frame: fresh.frame, app: fresh.app)
            }
            guard version == highlightVersion, !closed else { log["source"] = "superseded"; return }
            let words = lines.flatMap { $0 }
            log["wordsRead"] = words.count
            let trusted = DesktopAccessibility.isTrusted
            log["accessibility"] = trusted
            let pid = now.app.pid, window = now.frame
            var place: CGRect?
            var source = "none"
            if let cell {
                let range = target.label.contains(":") && StepCheck.references(in: "select \(target.label)").count == 1 ? target.label : cell.address
                if let found = ScreenText.excelCell(range, words: words) {
                    place = found; source = "screen-headings"
                } else if trusted, now.app.isExcel, let metrics = await selectionReader.cellMetrics(range),
                          let grid = await Task.detached(operation: { DesktopAccessibility.largest(role: "AXLayoutArea", pid: pid, in: window) }).value,
                          let measured = ExcelGeometry.choose(ExcelGeometry.candidates(metrics, grid: grid), near: estimate) {
                    place = measured; source = "excel-measured"
                }
            } else {
                let controls = trusted ? await Task.detached(operation: { DesktopAccessibility.controls(pid: pid, in: window) }).value : []
                let read = ScreenText.candidates(lines: lines)
                log["controls"] = controls.count
                if let snapped = TargetSnap.snap(box: estimate, label: target.label, candidates: controls) {
                    place = snapped; source = "accessibility"
                    log["matched"] = controls.first { $0.frame == snapped }?.name ?? ""
                } else if let snapped = TargetSnap.snap(box: estimate, label: target.label, candidates: read, byPosition: false) {
                    place = snapped; source = "screen-text"
                    log["matched"] = read.first { $0.frame == snapped }?.name ?? ""
                }
            }
            // Nothing on screen could confirm it (an icon with no visible name, and no Accessibility): still go to where
            // the model saw it, dashed so it reads as approximate, and say how to make it exact.
            if place == nil, let estimate {
                place = estimate
                source = "model-estimate"
                if !trusted, cell == nil, !shownAccessibilityTip {
                    shownAccessibilityTip = true
                    bubble.tip("Approximate. Turn on F2L under Accessibility so I can find icons exactly. Already on? Use Fix permissions in Pip's menu.",
                               action: "Open Settings") { DesktopAccessibility.openSettings() }
                }
            }
            log["source"] = source
            log["drawn"] = PointingDiagnostics.rect(place)
            guard version == highlightVersion, !closed, let place else { if version != highlightVersion { log["source"] = "superseded" }; return }
            replyCapture = now
            showTarget(now, place, verified: !source.hasPrefix("model"), cell: nil, sheet: nil, persistent: true)
        }
    }

    /// macOS keeps asking (or keeps saying no) when its Accessibility or Automation entry for F2L belongs to an older
    /// build. This clears F2L's own two entries, then asks once, fresh, for the current app.
    private func fixPermissions() {
        for service in ["Accessibility", "AppleEvents"] {
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", service, Bundle.main.bundleIdentifier ?? "ai.f2l.companion"]
            try? reset.run()
            reset.waitUntilExit()
        }
        shownAccessibilityTip = false
        DesktopAccessibility.requestTrust()
        say("Permissions cleared. Turn F2L on under Accessibility, then quit and reopen F2L. I'll ask about Excel the next time you ask a question in it.")
    }

    private func saveDiagnostics() {
        let app = capture.target()
        Task {
            let message = await PointingDiagnostics.save(app: app, capture: capture, excel: selectionReader)
            say(message)
        }
    }

    private func forgetPlaces() {
        replyCapture = nil
        replyTarget = nil
        stepTargets = []
        requestedCells = []
    }

    private func showTarget(_ captured: CapturedScreen, _ bounds: CGRect, verified: Bool, cell: CellReference?, sheet: String?, persistent: Bool = false) {
        guard CompanionPlacement.isUsable(bounds), ScreenCaptureService.isCurrent(captured),
              ScreenCaptureService.pointBelongsToWindow(captured.windowID, CGPoint(x: bounds.midX, y: bounds.midY)) else { return }
        targetPersistent = persistent
        targetCapture = captured
        targetCell = cell
        targetSheet = sheet
        targetShown = Date()
        if guide == nil { guide = GuideOverlayWindow() }
        guide?.show(bounds, verified: verified)
        // The input bar never sits on the place Pip is pointing at (unless the learner put it there).
        if !inputMoved, let input = panelRect, input.touches(TargetSnap.circle(around: bounds).insetBy(dx: -16, dy: -16)) {
            inputDodging = true
            layoutInputBar()
        }
        updateTeachingCompanion(bounds)
        positionBubble()
    }

    /// Every 0.4 s: approximate hints expire after 20 seconds or when the source window moves or loses focus;
    /// verified cells are looked up again, so the outline follows window moves and scrolling (MainWindow.WatchTarget).
    private func watchTarget() {
        guard let captured = targetCapture, !checkingHighlight else { return }
        guard let cell = targetCell else {
            // A lesson step keeps its hint while it is shown; other approximate hints expire after 20 seconds.
            if !ScreenCaptureService.isCurrent(captured) || (!targetPersistent && Date().timeIntervalSince(targetShown) > 20) { clearHighlight() }
            return
        }
        guard let current = ScreenCaptureService.refreshed(captured) else { clearHighlight(); return }
        checkingHighlight = true
        let version = highlightVersion
        Task {
            let result = await excel.resolve(current, cell)
            checkingHighlight = false
            guard version == highlightVersion, !closed else { return }
            if ScreenCaptureService.isCurrent(current), result.verified, result.sheet == targetSheet, let bounds = result.bounds {
                targetCapture = current
                guide?.show(bounds, verified: true)
                updateTeachingCompanion(bounds)
            } else {
                clearHighlight()
            }
        }
    }

    private func clearHighlight() {
        highlightVersion += 1
        guide?.close()
        guide = nil
        stopTeachingCompanion()
        lastTargetBounds = nil
        targetCapture = nil
        targetCell = nil
        targetSheet = nil
        if inputDodging { inputDodging = false; layoutInputBar() }
    }

    private func updateTeachingCompanion(_ target: CGRect) {
        lastTargetBounds = target
        if let captured = targetCapture, !ScreenCaptureService.isCurrent(captured) { stopTeachingCompanion(); return }
        guard followTargets, panelOpen, !isListening, !finishingDictation, !isRequestPending else { stopTeachingCompanion(); return }
        let width = min(max(pipSize.width * 0.8, 90), 144)
        let work = ScreenSpace.workArea(at: CGPoint(x: target.midX, y: target.midY))
        // Stand clear of the whole circle, not just the target inside it.
        guard let spot = CompanionPlacement.choose(target: TargetSnap.circle(around: target), work: work, size: CGSize(width: width, height: width * 340 / 320),
                                                   panel: panelRect, cursor: ScreenSpace.cursor, scale: 1, previous: teachingPip?.screenBounds)
        else { stopTeachingCompanion(); return }
        let follower = teachingPip ?? TeachingCompanionWindow()
        teachingPip = follower
        follower.onMove = { [weak self] in self?.positionBubble() }
        follower.reducedMotion = reducedMotion
        follower.pip.setIntent(questionIntent)
        follower.follow(spot, target: target, origin: homeRect, panel: panelRect)
        companionPanel.isHidden = true
    }

    private func stopTeachingCompanion() {
        teachingPip?.close()
        teachingPip = nil
        companionPanel.isHidden = false
        positionBubble()
    }

    /// Every 1.5 s while a reply about Excel is open: the card shows what is really selected and ticks steps.
    private func watchSelection() {
        guard selectionEnabled, screenSharingEnabled, panelOpen, bubble.isShowing, !selectionBusy, !closed,
              Date().timeIntervalSince(lastSelectionRead) > 1.5 else { return }
        guard capture.target()?.isExcel == true else { return }
        selectionBusy = true
        lastSelectionRead = Date()
        let version = turn
        Task {
            let result = await selectionReader.read()
            selectionBusy = false
            guard version == turn, !closed, screenSharingEnabled, selectionEnabled, capture.target()?.isExcel == true else { return }
            bubble.updateSelection(result.context, line: result.message)
        }
    }

    private func newChat() {
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
        say(Self.greeting)
    }

    // MARK: - Dictation (mirrors Talk_Click)

    private func talk() {
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
    private func applyTranscript(_ transcript: String) {
        let spoken = String(transcript.dropFirst(consumedTranscript)).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = dictationPrefix
        let joined = prefix.isEmpty || spoken.isEmpty ? prefix + spoken
            : prefix + (prefix.last?.isWhitespace == true ? "" : " ") + spoken
        guard composer.string != joined else { return }
        applyingTranscript = true
        setComposer(joined)
        applyingTranscript = false
    }

    private func stopDictation() {
        dictationSession += 1
        if isListening || finishingDictation { dictation.cancel() }
        isListening = false
        finishingDictation = false
        pipHost.pip.setListening(false)
        micButton.title = "◉"
        setPlaceholder(Self.askPlaceholder)
    }

    // MARK: - Settings, saving, quitting

    private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow.make() }
        NSApp.activate()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func saveConversation() {
        if !store.save(session, draft: composer.string) { Log.app.error("Couldn't save the conversation") }
    }

    func shutdown() {
        guard !closed else { return }
        cancelCurrentTurn()
        closed = true
        intro?.finish()
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
        updateTeachingCompanion(target)
    }

    func greet() { say(Self.greeting) }
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
