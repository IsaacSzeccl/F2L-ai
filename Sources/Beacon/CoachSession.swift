import AppKit
import CoachCore
import Foundation

enum CoachPhase: Equatable {
    case idle, listening, thinking, speaking
}

/// State the island shows.
@MainActor
final class IslandModel: ObservableObject {
    @Published var phase: CoachPhase = .idle
    @Published var heard = ""
    @Published var reply = ""
    @Published var status = "Hold the right ⌥ Option key and talk"
    @Published var latency = ""
    @Published var paused = false
    @Published var hasError = false
    @Published var expanded = false
    /// Width of the camera housing on notched MacBooks (0 elsewhere); the island lays out around it.
    @Published var notchWidth: CGFloat = 0
    /// Microphone loudness 0...1 while listening.
    @Published var micLevel: Double = 0
    /// The text box has focus or text in it: keep the bar open.
    @Published var inputActive = false
    /// Bumped to ask the text box to take keyboard focus.
    @Published var focusRequest = 0
}

/// The orchestrator: push-to-talk → transcript → screen context → LLM (streamed) → voice + circle.
///
/// Every turn gets an id. Anything a turn does after an `await` first checks it is still the current
/// turn, so a barge-in or "Start over" can never be overwritten by a turn that was cancelled mid-flight.
@MainActor
final class CoachSession {
    let model: IslandModel
    let overlay: OverlayController
    let speechOutput = SpeechOutput()

    private let reader = AccessibilityReader()
    private let speechInput = SpeechInput()
    private let watcher: TargetWatcher

    private var history: [ChatMessage] = []
    /// What the coach did on screen last turn, told to the model as context rather than written into its
    /// own words (where it would imitate and speak it).
    private var lastActions: [String] = []
    private var turnTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var currentTurn: UUID?
    /// The turn still being worked on (context, LLM stream). Speech finishing between sentences
    /// mustn't end it.
    private var runningTurn: UUID?
    private var latency = TurnLatency()

    /// A nudge that arrived while the coach was busy, delivered once it falls quiet.
    private var pendingEvent: (event: StepEvent, at: Date)?

    private var lastExternalApp: NSRunningApplication?
    private var annotatedPID: pid_t?

    private var summaries: [String: String] = [:]
    private var summaryInFlight: String?
    private var summaryTimer: Timer?
    private var activationObserver: Any?

    init(model: IslandModel, overlay: OverlayController) {
        self.model = model
        self.overlay = overlay
        self.watcher = TargetWatcher(reader: reader)

        speechInput.onPartial = { [weak self] text in
            guard let self, self.model.phase == .listening else { return }
            self.model.heard = text
        }
        speechInput.onLevel = { [weak self] level in self?.model.micLevel = Double(level) }
        speechOutput.onFirstAudio = { [weak self] in self?.markFirstAudio() }
        speechOutput.onFinished = { [weak self] in self?.speechFinished() }
        watcher.onFrameChanged = { [weak self] frame in self?.overlay.move(to: frame) }
        watcher.onTargetLost = { [weak self] in self?.clearPointer() }
        watcher.onEvent = { [weak self] event in self?.handle(event) }

        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own {
            lastExternalApp = front
            reader.prepare(front)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.appActivated(app) }
        }
        summaryTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshSummary() }
        }
    }

    // MARK: - Push to talk

    func beginListening() {
        guard model.phase != .listening else { return }
        cancelTurn() // barge-in: silence the coach and abandon whatever it was doing
        model.phase = .listening
        model.heard = ""
        model.hasError = false
        model.status = "Listening… let go when you're done"
        do {
            try speechInput.start()
        } catch {
            model.phase = .idle
            showError("I can't hear you: \(error.localizedDescription)")
        }
    }

    func endListening(cancelled: Bool) {
        guard model.phase == .listening else { return }
        let released = Date() // latency is measured from the moment the key is let go
        // Leave .listening right away so a quick re-press starts a fresh recording.
        model.phase = .thinking
        model.status = "Thinking…"
        listenTask = Task {
            let transcript = await speechInput.stop()
            model.micLevel = 0
            guard !Task.isCancelled else { return }
            listenTask = nil
            latency = TurnLatency()
            latency.speechEnded = released
            guard !cancelled, !transcript.isEmpty else {
                model.phase = .idle
                if cancelled {
                    model.status = "Cancelled"
                } else {
                    // Say why, not just "didn't catch that": a silent microphone and a mis-heard word need different fixes.
                    model.status = speechInput.stats.diagnosis ?? "I didn't catch that. Hold right ⌥ and try again."
                    model.hasError = speechInput.stats.diagnosis != nil
                }
                return
            }
            model.heard = transcript
            startTurn(prompt: PromptBuilder.learnerUtterance(transcript), freshFrame: ScreenReference.needsFreshFrame(transcript))
        }
    }

    // MARK: - Typed questions

    /// The same path as a spoken question, starting from text.
    func submitText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if model.phase == .listening { speechInput.cancel() }
        cancelTurn()
        latency = TurnLatency()
        latency.speechEnded = Date()
        model.heard = trimmed
        model.hasError = false
        startTurn(prompt: PromptBuilder.learnerUtterance(trimmed), freshFrame: ScreenReference.needsFreshFrame(trimmed))
    }

    // MARK: - Controls

    func togglePause() {
        model.paused.toggle()
        if model.paused {
            clearPointer()
            pendingEvent = nil
            model.status = "Paused. Beacon can't see your screen."
        } else {
            model.status = "Back on. Hold right ⌥ and talk."
        }
    }

    func clearPointer() {
        watcher.stop()
        overlay.clear()
        annotatedPID = nil
    }

    func resetConversation() {
        cancelTurn()
        speechInput.cancel()
        history.removeAll()
        lastActions.removeAll()
        clearPointer()
        model.phase = .idle
        model.heard = ""
        model.reply = ""
        model.status = "New conversation. Hold right ⌥ and talk."
    }

    func testVoice() {
        speechOutput.stop()
        speechOutput.beginReply()
        speechOutput.enqueue("Hi, I'm Beacon. Hold the right Option key whenever you want to ask me something.")
    }

    private func cancelTurn() {
        speechOutput.stop()
        listenTask?.cancel()
        listenTask = nil
        turnTask?.cancel()
        turnTask = nil
        currentTurn = nil
        runningTurn = nil
        pendingEvent = nil
    }

    // MARK: - Turns

    private func handle(_ event: StepEvent) {
        guard !model.paused else { return }
        switch event {
        case .clicked, .submitted: clearPointer() // that step is done
        case .typed: break
        }
        guard model.phase == .idle else {
            // Never interrupt the learner or the coach; say it when the coach falls quiet.
            pendingEvent = (event, Date())
            return
        }
        deliver(event)
    }

    private func deliver(_ event: StepEvent) {
        latency = TurnLatency()
        latency.speechEnded = Date()
        let fresh: Bool = if case .typed = event { false } else { true }
        startTurn(prompt: PromptBuilder.screenEvent(event.description), freshFrame: fresh)
    }

    private func startTurn(prompt: String, freshFrame: Bool) {
        turnTask?.cancel()
        pendingEvent = nil
        let id = UUID()
        currentTurn = id
        runningTurn = id
        turnTask = Task { await runTurn(id: id, prompt: prompt, freshFrame: freshFrame) }
    }

    private func isCurrent(_ id: UUID) -> Bool { currentTurn == id && !Task.isCancelled }

    private func runTurn(id: UUID, prompt: String, freshFrame: Bool) async {
        model.phase = .thinking
        model.reply = ""
        model.status = "Thinking…"
        let (context, references) = await buildContext(freshFrame: freshFrame)
        guard isCurrent(id) else { return }

        let learnerText = lastActions.isEmpty ? prompt : "(On screen after your last reply: \(lastActions.joined(separator: "; ")).)\n\(prompt)"
        let messages = PromptBuilder.messages(history: history, context: context, learnerText: learnerText, attachScreenshot: context.screenshot != nil)
        let client = LLMClients.make(Preferences.llmSettings())
        var chunker = SentenceChunker()
        var spoken = ""
        var actions: [String] = []
        var lastCaption: String?
        var drewCircle = false
        var missedTarget = false
        enqueuedSpeech = false

        speechOutput.beginReply()
        latency.requestSent = Date()

        do {
            for try await event in client.stream(messages: messages, tools: CoachTools.all) {
                guard isCurrent(id) else { return }
                if latency.firstToken == nil { latency.firstToken = Date() }
                switch event {
                case let .text(text):
                    spoken += text
                    model.reply = spoken
                    for sentence in chunker.append(text) { speak(sentence, turn: id) }
                case let .toolCall(call):
                    let result = await apply(call, context: context, references: references, turn: id)
                    guard isCurrent(id) else { return }
                    switch result {
                    case let .drew(action, caption):
                        actions.append(action)
                        drewCircle = true
                        lastCaption = caption ?? lastCaption
                    case .cleared:
                        actions.append("you cleared the circle")
                    case .notOnScreen:
                        missedTarget = true
                    case .ignored:
                        break
                    }
                }
            }
            // A cancelled stream ends quietly rather than throwing: don't speak its half-finished sentence.
            guard isCurrent(id) else { return }
            if let rest = chunker.finish() { speak(rest, turn: id) }
            if !enqueuedSpeech, drewCircle || missedTarget {
                // Some models answer with only a tool call. Never leave the learner in silence.
                let line = drewCircle
                    ? (lastCaption.map { "Have a look at the circle on your screen: \($0)." } ?? "Have a look at the circle on your screen.")
                    : "Hmm, I couldn't find that on your screen. Could you tell me what you see?"
                spoken = line
                model.reply = line
                speak(line, turn: id)
            }
        } catch {
            guard isCurrent(id) else { return }
            Log.llm.error("Turn failed: \(error.localizedDescription, privacy: .public)")
            let apology = "Sorry, I couldn't reach the AI service just now. Please try again in a moment."
            model.reply = apology
            speak(apology, turn: id)
            showError(error.localizedDescription)
        }
        guard isCurrent(id) else { return }

        history.append(ChatMessage(role: .user, text: prompt))
        let said = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        history.append(ChatMessage(role: .assistant, text: said.isEmpty ? "(no reply)" : said))
        lastActions = actions
        if history.count > 40 { history.removeFirst(history.count - 40) }

        runningTurn = nil
        if !speechOutput.isSpeaking { speechFinished() }
    }

    private var enqueuedSpeech = false

    private func speak(_ sentence: String, turn id: UUID) {
        guard isCurrent(id) else { return }
        enqueuedSpeech = true
        speechOutput.enqueue(sentence)
        model.phase = .speaking
    }

    private enum ApplyResult {
        case drew(action: String, caption: String?)
        case cleared
        case notOnScreen
        case ignored
    }

    /// Applies one tool call to the overlay.
    private func apply(_ call: ToolCall, context: ScreenContext, references: [String: AXUIElement], turn turnID: UUID) async -> ApplyResult {
        guard let command = CoachTools.parse(call) else {
            Log.llm.error("Unusable tool call \(call.name, privacy: .public) \(call.argumentsJSON, privacy: .public)")
            return .ignored
        }
        if command == .clear {
            clearPointer()
            return .cleared
        }
        guard let annotation = CoachTools.resolve(command, in: context) else {
            Log.llm.error("Model pointed at something not on screen: \(call.argumentsJSON, privacy: .public)")
            return .notOnScreen
        }
        if let elementID = annotation.elementID, let element = references[elementID], let screenElement = context.element(withID: elementID) {
            let current = await reader.state(of: element)
            guard isCurrent(turnID) else { return .ignored }
            overlay.show(annotation)
            annotatedPID = lastExternalApp?.processIdentifier
            watcher.watch(element: element, annotation: annotation, label: screenElement.label, initialValue: current.value ?? "")
            return .drew(action: "you circled \"\(screenElement.label)\"", caption: annotation.caption ?? screenElement.label)
        }
        overlay.show(annotation)
        annotatedPID = lastExternalApp?.processIdentifier
        watcher.stop()
        return .drew(action: "you roughly circled \(annotation.caption ?? "an area")", caption: annotation.caption)
    }

    private func speechFinished() {
        guard runningTurn == nil, listenTask == nil, model.phase == .speaking || model.phase == .thinking else { return }
        model.phase = .idle
        if !model.hasError { model.status = "Hold right ⌥ to reply" }
        if let pending = pendingEvent {
            pendingEvent = nil
            if Date().timeIntervalSince(pending.at) < 10, !model.paused { deliver(pending.event) }
        }
    }

    private func markFirstAudio() {
        guard latency.firstAudio == nil else { return }
        latency.firstAudio = Date()
        let summary = latency.summary()
        Log.latency.info("\(summary, privacy: .public)")
        if let start = latency.speechEnded, let end = latency.firstAudio {
            model.latency = String(format: "%.1fs to first word", end.timeIntervalSince(start))
        }
    }

    private func showError(_ message: String) {
        model.hasError = true
        model.status = message
    }

    // MARK: - Screen context

    /// The app the learner is working in. The island never takes focus, but Settings and onboarding do,
    /// so fall back to the last other app that was in front.
    private func targetApp() -> NSRunningApplication? {
        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own { return front }
        return lastExternalApp
    }

    func buildContext(freshFrame: Bool, forceScreenshot: Bool = false) async -> (ScreenContext, [String: AXUIElement]) {
        if model.paused {
            return (ScreenContext(appName: "(screen sharing paused)", windowTitle: "", windowFrame: .zero, elements: [],
                                  summary: "The learner paused screen sharing. You cannot see their screen, but you can still talk and answer questions."), [:])
        }
        guard let app = targetApp() else {
            return (ScreenContext(appName: "(no app in front)", windowTitle: "", windowFrame: .zero, elements: []), [:])
        }
        let snapshot = await reader.snapshot(of: app)
        var context = ScreenContext(
            appName: snapshot.appName,
            windowTitle: snapshot.windowTitle,
            windowFrame: snapshot.windowFrame,
            elements: snapshot.elements,
            summary: summaries["\(snapshot.pid)|\(snapshot.windowTitle)"]
        )
        let wantsScreenshot = freshFrame || forceScreenshot || snapshot.elements.count < 3
        if wantsScreenshot, let capture = await safeCapture(app: app, near: snapshot.windowFrame) {
            context.screenshot = capture.image
            context.windowFrame = capture.windowFrame
        } else if wantsScreenshot {
            context.summary = [context.summary, "No screenshot this time (a password box may be selected)."].compactMap { $0 }.joined(separator: " ")
        }
        Log.screen.debug("Context: \(snapshot.appName, privacy: .public) – \(snapshot.elements.count) controls, screenshot: \(context.screenshot != nil)")
        return (context, snapshot.references)
    }

    /// Captures the front window unless paused or a password box is focused. The focus check runs
    /// immediately before the capture, not earlier, so focus moving into a password box is respected.
    private func safeCapture(app: NSRunningApplication, near frame: CGRect) async -> ScreenCapturer.Capture? {
        guard !model.paused else { return nil }
        let (secure, liveFrame) = await reader.secureFocusAndFrame(of: app)
        guard !secure, !model.paused else { return nil }
        do {
            return try await ScreenCapturer.captureFrontWindow(pid: app.processIdentifier, near: liveFrame.isEmpty ? frame : liveFrame)
        } catch {
            Log.screen.error("Screenshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func appActivated(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApp = app
        reader.prepare(app)
        // The circle belongs to the app it was drawn on; don't leave it pointing at stale UI.
        if let annotatedPID, annotatedPID != app.processIdentifier { clearPointer() }
    }

    // MARK: - Background summary loop

    /// When the front window changes, ask the small vision model for a one-line description.
    /// Turns that don't need a fresh screenshot use this cached line instead. Disclosed on the start
    /// screen, and can be turned off in Settings.
    private func refreshSummary() async {
        guard Preferences.summaryLoopEnabled, !model.paused, model.phase == .idle, summaryInFlight == nil,
              let app = targetApp() else { return }
        let signature = await reader.windowSignature(of: app)
        guard summaries[signature] == nil else { return }
        summaryInFlight = signature
        defer { summaryInFlight = nil }

        guard let capture = await safeCapture(app: app, near: .zero) else { return }
        let client = LLMClients.make(Preferences.llmSettings(summary: true))
        var text = ""
        do {
            for try await event in client.stream(messages: [ChatMessage(role: .user, text: PromptBuilder.summaryPrompt, image: capture.image)], tools: []) {
                if case let .text(t) = event { text += t }
            }
        } catch {
            Log.llm.debug("Summary failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if summaries.count > 50 { summaries.removeAll() }
        summaries[signature] = String(line.prefix(240))
    }

    // MARK: - Spike snapshots (developer mode only)

    /// Saves the current front window as a spike test case. This is the only thing Beacon ever writes
    /// to disk about the screen, and only in developer mode (see SETUP.md).
    func saveSpikeSnapshot() async -> URL? {
        let (context, _) = await buildContext(freshFrame: true, forceScreenshot: true)
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Beacon/spike-cases", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "case-\(Int(Date().timeIntervalSince1970))"
        let spikeCase = SpikeCase(name: name, question: "EDIT ME: what the learner asks", context: context, expectedElementID: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(spikeCase) else { return nil }
        let url = folder.appendingPathComponent("\(name).json")
        do {
            try data.write(to: url)
            if let image = context.screenshot, let jpeg = Data(base64Encoded: image.jpegBase64) {
                try jpeg.write(to: folder.appendingPathComponent("\(name).jpg"))
            }
            return url
        } catch {
            Log.app.error("Could not save spike snapshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
