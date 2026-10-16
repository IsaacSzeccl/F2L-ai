import AppKit
import CoachCore

/// Pip's reply card beside the character: words appear one by one, and a lesson moves one step at a time with
/// Done / Show me again / I'm stuck and ticks Excel steps by itself.
/// Mirrors Windows/F2L.Windows/ReplyBubbleWindow.cs.
@MainActor
final class ReplyBubble: CompanionPanel {
    fileprivate enum Page: Equatable {
        case text(String, last: Bool)
        case step(Int)
        case finished
    }

    private let box = RoundedBox(fill: Palette.panel, radius: 22, border: Palette.panelBorder)
    private let selection = makeLabel("", size: 11, color: Palette.verified, wraps: true)
    /// What the lesson achieves, shown above its steps (a lesson starts straight at step 1).
    private let summary = makeLabel("", size: 12, color: Palette.hex(0x82858D), wraps: true)
    private let counter = makeLabel("", size: 10, weight: .medium, color: Palette.lavenderInk)
    private let text = NSTextField(wrappingLabelWithString: "")
    /// While words appear, a click shows them all at once; afterwards the text can be selected and copied.
    private let reveal = NSClickGestureRecognizer()
    private let status = makeLabel("", size: 12, weight: .medium, color: Palette.verified, wraps: true)
    private let closeButton = FlatButton("×", size: 15, ink: Palette.hex(0x9699A2), fill: nil)
    private let back = FlatButton("←", size: 13, ink: Palette.hex(0x9699A2), fill: nil)
    /// Copies everything Pip said in this card (all pages, or the lesson's summary and every step).
    private let copyButton = FlatButton("Copy", size: 11, ink: Palette.hex(0x9699A2), fill: nil)
    private var buttons: [FlatButton] = []

    private var steps: [String] = []
    private var pages: [Page] = []
    private var index = 0
    private var areas: [String] = []
    private var areasAtStepStart: [String] = []
    private var ticked = false
    private var timer: Timer?
    private var advanceTimer: Timer?
    private var started = Date()
    private var words: [NSRange] = []
    private var anchor = CGRect.zero
    private var protectedTarget: CGRect?
    private var inputBounds: CGRect?

    /// The learner asked for help with a step ("I'm stuck") or for more ("Explain more"): ask Pip this question.
    var onAsk: ((String) -> Void)?
    /// Moving to another page clears the screen highlight of the previous one.
    var onPage: (() -> Void)?
    /// What the shown page is about, so Pip can go to that place on screen.
    enum Focus: Equatable { case reply, step(Int), nothing }
    var onFocus: ((Focus) -> Void)?
    /// A ticked step: Pip waves.
    var onCelebrate: (() -> Void)?
    private let emoteView = NSImageView()
    private var emote: PipEmote?
    private var sayEmote: PipEmote?
    /// The buttons under a short line: things to choose, such as what to learn. Empty for a plain line.
    typealias Choice = (title: String, primary: Bool, action: () -> Void)
    private var sayChoices: [Choice] = []
    var onAskSomethingElse: (() -> Void)?
    /// The card was closed (answered, finished or hidden): Pip goes back to resting.
    var onDismiss: (() -> Void)?
    var reducedMotion = false { didSet { if reducedMotion { finishReveal() } } }
    var isShowing: Bool { !pages.isEmpty }
    var isLesson: Bool { !steps.isEmpty }

    override init() {
        super.init()
        title = "Pip’s reply"
        contentView = box
        hasShadow = true
        level = .statusBar
        text.isSelectable = false
        text.allowsEditingTextAttributes = true // keeps Pip's font and colour while text is selected
        text.setAccessibilityLabel("Pip’s reply")
        closeButton.padding = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        closeButton.toolTip = "Hide Pip’s reply"
        closeButton.setAccessibilityLabel("Hide Pip’s reply")
        closeButton.onClick = { [weak self] in self?.dismiss() }
        back.padding = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        back.toolTip = "Previous step"
        back.setAccessibilityLabel("Previous step")
        back.onClick = { [weak self] in self?.go(to: (self?.index ?? 1) - 1) }
        copyButton.padding = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        copyButton.toolTip = "Copy what Pip said"
        copyButton.setAccessibilityLabel("Copy what Pip said")
        copyButton.onClick = { [weak self] in self?.copyAll() }
        [selection, summary, counter, emoteView, text, status, closeButton, back, copyButton].forEach(box.addSubview)
        emoteView.imageScaling = .scaleProportionallyUpOrDown
        emoteView.setAccessibilityElement(false)
        reveal.target = self
        reveal.action = #selector(textClicked)
        text.addGestureRecognizer(reveal)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Content

    /// A short line from Pip with no lesson: a greeting, "Thinking…" or a problem, with one of Pip's own emotes
    /// (never a system emoji) and optionally buttons to choose from.
    func say(_ line: String, emote: PipEmote? = nil, choices: [Choice] = []) {
        steps = []
        summary.stringValue = ""
        sayEmote = emote
        sayChoices = choices
        pages = [.text(line, last: true)]
        go(to: 0, buttons: !choices.isEmpty)
        orderFrontRegardless()
    }

    func show(reply: String, steps: [String] = []) {
        self.steps = steps
        sayEmote = nil
        sayChoices = []
        summary.stringValue = steps.isEmpty ? "" : Self.withoutEmoji(TeachingReply.clean(reply))
        if steps.isEmpty {
            let paragraphs = ReplyPhrases.pages(reply: reply, steps: [])
            pages = paragraphs.enumerated().map { .text($0.element, last: $0.offset == paragraphs.count - 1) }
            if pages.isEmpty { pages = [.text(TeachingReply.clean(reply), last: true)] }
        } else {
            pages = steps.indices.map { .step($0) } + [.finished]
        }
        go(to: 0)
        orderFrontRegardless()
    }

    func resume() { if isShowing { orderFrontRegardless() } }

    func dismiss() {
        timer?.invalidate(); timer = nil
        advanceTimer?.invalidate(); advanceTimer = nil
        orderOut(nil)
        let wasShowing = !pages.isEmpty
        pages = []; steps = []
        if wasShowing { onDismiss?() }
    }

    /// Excel's live selection: shown on the card, and used to tick selection steps the learner has really done.
    func updateSelection(_ context: ExcelContext?, line: String) {
        if selection.stringValue != line {
            selection.stringValue = line
            selection.toolTip = line
            arrange()
        }
        areas = context?.areas ?? []
        checkStep()
    }

    private func checkStep() {
        guard pages.indices.contains(index), case .step(let number) = pages[index], !ticked, !areas.isEmpty, areas != areasAtStepStart
        else { return }
        switch StepCheck.check(step: steps[number], earlier: Array(steps[..<number]), selected: areas) {
        case .done:
            ticked = true
            setStatus("That’s it! Excel shows \(areas.joined(separator: ", ")).", good: true)
            setEmote(.cheer)
            onCelebrate?()
            advanceSoon()
        case .missing(let needed):
            setStatus("Not yet: \(needed.joined(separator: ", ")) still \(needed.count == 1 ? "needs" : "need") selecting.", good: false)
        case .notCheckable:
            break
        }
    }

    /// After a ticked step, a moment to see the tick, then the next step.
    private func advanceSoon() {
        let timer = Timer(timeInterval: reducedMotion ? 0.6 : 1.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.go(to: (self?.index ?? 0) + 1) }
        }
        RunLoop.main.add(timer, forMode: .common)
        advanceTimer = timer
    }

    /// The step on screen, while it isn't ticked yet.
    var currentStep: String? {
        guard pages.indices.contains(index), case .step(let number) = pages[index], !ticked else { return nil }
        return steps[number]
    }

    static let keyNames = ["shift": "Shift", "command": "Command", "control": "Control", "option": "Option"]

    /// The learner clicked the circled place, holding `held` keys. A click step is done and the lesson moves on (if
    /// the keys it says to hold were held); a step that also needs typing or dragging says what is left; a plain
    /// answer is marked done.
    func clickedTarget(held: Set<String> = []) {
        guard pages.indices.contains(index), !ticked else { return }
        switch pages[index] {
        case .step(let number):
            let missing = ClickWatch.requiredKeys(steps[number]).subtracting(held)
            guard missing.isEmpty else {
                let keys = missing.sorted().compactMap { Self.keyNames[$0] }.joined(separator: " and ")
                setStatus("Almost: hold \(keys) while you click.", good: false)
                return
            }
            guard ClickWatch.finishesOnClick(steps[number]) else {
                setStatus(ClickWatch.isTypingStep(steps[number]) ? "Good, that’s the place. Now type it; I’ll move on when you stop."
                                                               : "Good, that’s the place. Finish this step there, then press Done.", good: true)
                return
            }
            ticked = true
            setStatus("That’s it!", good: true)
            setEmote(.cheer)
            onCelebrate?()
            advanceSoon()
        case .text:
            ticked = true
            setStatus("That’s it!", good: true)
            setEmote(.cheer)
            onCelebrate?()
        case .finished:
            break
        }
    }

    /// A short note under the current step, such as "You're already there".
    func note(_ line: String) { if currentStep != nil { setStatus(line, good: true) } }

    /// Takes back a note set with `note`, unless something else has replaced it since.
    func clearNote(_ line: String) {
        guard status.stringValue == line else { return }
        status.stringValue = ""
        arrange()
    }

    /// F2L saw the step happen (the box got text, the app or page came to the front): tick it and move on.
    func stepDone() {
        guard currentStep != nil else { return }
        ticked = true
        setStatus("That’s it!", good: true)
        setEmote(.cheer)
        onCelebrate?()
        advanceSoon()
    }

    // MARK: - Pages

    private func go(to page: Int, buttons showButtons: Bool = true) {
        guard pages.indices.contains(page) else { return }
        if page != index { onPage?() }
        advanceTimer?.invalidate(); advanceTimer = nil
        index = page
        ticked = false
        areasAtStepStart = areas
        status.stringValue = ""
        buildButtons(showButtons)
        emote = pages[page] == .finished ? .cheer : sayEmote
        emoteView.image = emote?.image(side: 44)
        emoteView.isHidden = emote == nil
        let line = phrase
        words = ReplyPhrases.words(in: line)
        setSelectable(false)
        text.attributedStringValue = Self.body(line, color: Palette.ink)
        text.setAccessibilityValue(line)
        NSAccessibility.post(element: text, notification: .valueChanged)
        switch pages[page] {
        case .step(let number): counter.stringValue = "STEP \(number + 1) OF \(steps.count)"
        default: counter.stringValue = ""
        }
        back.isHidden = !(pages[page].isStep && page > 0)
        arrange()
        startReveal()
        onFocus?(showButtons ? focus : .nothing)
    }

    private var focus: Focus {
        guard pages.indices.contains(index) else { return .nothing }
        switch pages[index] {
        case .step(let number): return .step(number)
        case .text: return index == 0 && steps.isEmpty ? .reply : .nothing
        default: return .nothing
        }
    }

    private var phrase: String { Self.withoutEmoji(rawPhrase) }

    /// Pip's card never shows emoji, even if a reply contains some.
    static func withoutEmoji(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { s in
            !(s.properties.isEmoji && s.value >= 0x203C) && s.value != 0xFE0F && s.value != 0x200D && !(0x1F3FB...0x1F3FF).contains(s.value)
        })
        return String(scalars).replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    private var rawPhrase: String {
        guard pages.indices.contains(index) else { return "" }
        switch pages[index] {
        case .text(let line, _): return line
        case .step(let number): return steps[number]
        case .finished: return steps.isEmpty ? "" : "All done. You did every step."
        }
    }

    private func buildButtons(_ show: Bool) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        guard show, pages.indices.contains(index) else { return }
        func add(_ title: String, primary: Bool = false, _ action: @escaping () -> Void) {
            let button = FlatButton(title, size: 12, ink: primary ? .white : Palette.ink, fill: primary ? Palette.send : Palette.button)
            button.weight = primary ? .semibold : .regular
            button.padding = NSEdgeInsets(top: 7, left: 13, bottom: 7, right: 13)
            button.onClick = action
            buttons.append(button)
        }
        switch pages[index] {
        case .text(let line, let last):
            if !sayChoices.isEmpty {
                for choice in sayChoices { add(choice.title, primary: choice.primary) { [weak self] in self?.dismiss(); choice.action() } }
            } else if !last { add("Next →", primary: true) { [weak self] in self?.go(to: (self?.index ?? 0) + 1) } }
            else if line != ConversationSession.pendingText {
                add("Got it", primary: true) { [weak self] in self?.dismiss() }
                add("Explain more") { [weak self] in self?.onAsk?("Explain that a little more, with an example.") }
            }
        case .step(let number):
            add("Done", primary: true) { [weak self] in self?.go(to: (self?.index ?? 0) + 1) }
            add("Show me again") { [weak self] in self?.replay() }
            add("I’m stuck") { [weak self] in
                guard let self else { return }
                onAsk?("I'm stuck on step \(number + 1): \(steps[number]) What should I do from here?")
            }
        case .finished:
            add("Ask something else", primary: true) { [weak self] in self?.dismiss(); self?.onAskSomethingElse?() }
            add("Start again") { [weak self] in self?.go(to: 0) }
        }
        buttons.forEach(box.addSubview)
    }

    private func replay() {
        onPage?()
        onFocus?(focus)
        ticked = false
        areasAtStepStart = areas
        status.stringValue = ""
        arrange()
        startReveal()
    }

    /// A recipe's own advice for when a button isn't where the recipe says, shown with nothing to press. Unlike
    /// `note`, it reads as a caution and shows whether or not a step is the current one.
    func advice(_ line: String) {
        guard !ticked else { return }
        setStatus(line, good: false)
        arrange()
    }

    /// A short note under the current page with one action, such as how to make pointing exact.
    func tip(_ line: String, action title: String, _ action: @escaping () -> Void) {
        guard !ticked else { return }
        setStatus(line, good: false)
        let button = FlatButton(title, size: 12, fill: Palette.button)
        button.padding = NSEdgeInsets(top: 7, left: 13, bottom: 7, right: 13)
        button.onClick = action
        buttons.append(button)
        box.addSubview(button)
        arrange()
    }

    private func setEmote(_ new: PipEmote?) {
        emote = new
        emoteView.image = new?.image(side: 44)
        emoteView.isHidden = new == nil
        arrange()
    }

    private func setStatus(_ line: String, good: Bool) {
        status.stringValue = line
        status.textColor = good ? Palette.verified : Palette.approximate
        arrange()
    }

    // MARK: - Word by word

    static func body(_ string: String, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return NSAttributedString(string: string, attributes: [.font: Fonts.inter(16), .foregroundColor: color, .paragraphStyle: paragraph])
    }

    /// Selection is off while words appear (a selection would show the hidden words) and on once the line is whole.
    private func setSelectable(_ on: Bool) {
        if !on, text.currentEditor() != nil { makeFirstResponder(nil) }
        text.isSelectable = on
        reveal.isEnabled = !on
    }

    private func startReveal() {
        timer?.invalidate()
        setSelectable(false)
        started = Date()
        setButtonsVisible(false)
        if reducedMotion || words.isEmpty { finishReveal(); return }
        drawWords()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.drawWords() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let pop = CABasicAnimation(keyPath: "transform.translation.y")
        pop.fromValue = 7; pop.toValue = 0; pop.duration = 0.22
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        box.layer?.add(pop, forKey: "phrase-pop")
    }

    private func drawWords() {
        let progress = Date().timeIntervalSince(started) / 0.14
        if progress >= Double(words.count) { finishReveal(); return }
        let line = phrase
        let value = NSMutableAttributedString(attributedString: Self.body(line, color: .clear))
        for (word, range) in words.enumerated() where NSMaxRange(range) <= (line as NSString).length {
            let opacity = min(1, max(0, (progress - Double(word)) / 0.8))
            if opacity > 0 { value.addAttribute(.foregroundColor, value: Palette.ink.withAlphaComponent(opacity), range: range) }
        }
        text.attributedStringValue = value
    }

    func finishReveal() {
        timer?.invalidate(); timer = nil
        text.attributedStringValue = Self.body(phrase, color: Palette.ink)
        setSelectable(true)
        setButtonsVisible(true)
        checkStep()
    }

    private func setButtonsVisible(_ visible: Bool) {
        for button in buttons {
            button.isHidden = !visible
            if visible, !reducedMotion {
                button.alphaValue = 0
                NSAnimationContext.runAnimationGroup { $0.duration = 0.2; button.animator().alphaValue = 1 }
            }
        }
    }

    @objc private func textClicked() { if timer != nil { finishReveal() } }

    /// Everything in the card as plain text, the way it reads: a reply's pages, or a lesson's summary and its steps.
    var copyableText: String {
        if !steps.isEmpty {
            let numbered = steps.enumerated().map { "\($0.offset + 1). \(Self.withoutEmoji($0.element))" }
            return ([summary.stringValue].filter { !$0.isEmpty } + numbered).joined(separator: "\n")
        }
        return pages.compactMap { page -> String? in
            if case .text(let line, _) = page { return Self.withoutEmoji(line) } else { return nil }
        }.joined(separator: "\n\n")
    }

    private func copyAll() {
        let value = copyableText
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        setCopyTitle("Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.setCopyTitle("Copy") }
    }

    private func setCopyTitle(_ title: String) {
        copyButton.title = title
        copyButton.textSize = 11 // restyles the new title
    }

    // MARK: - Placement

    func follow(_ rect: CGRect, avoiding target: CGRect? = nil, input: CGRect? = nil) {
        anchor = rect; protectedTarget = target; inputBounds = input
        arrange()
    }

    private func arrange() {
        let work = ScreenSpace.workArea(at: CGPoint(x: anchor.midX, y: anchor.midY))
        let width = min(360, work.width - 24)
        let inner = width - 36
        func height(_ field: NSTextField) -> CGFloat {
            field.stringValue.isEmpty ? 0 : ceil(field.attributedStringValue.boundingRect(
                with: NSSize(width: inner, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2
        }
        var y: CGFloat = 16
        let selectionHeight = height(selection)
        selection.frame = NSRect(x: 18, y: y, width: inner - 20, height: selectionHeight)
        if selectionHeight > 0 { y += selectionHeight + 8 }
        let summaryHeight = height(summary)
        summary.frame = NSRect(x: 18, y: y, width: inner - 40, height: summaryHeight)
        if summaryHeight > 0 { y += summaryHeight + 6 }
        let counterHeight: CGFloat = counter.stringValue.isEmpty ? 0 : 14
        counter.frame = NSRect(x: 18, y: y, width: inner - 20, height: counterHeight)
        if counterHeight > 0 { y += counterHeight + 6 }
        // Pip's emote sits left of the words when there is one.
        let indent: CGFloat = emote == nil ? 0 : 52
        let measured = ceil(Self.body(phrase, color: Palette.ink).boundingRect(
            with: NSSize(width: inner - indent - 24, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 4
        emoteView.frame = NSRect(x: 14, y: y - 8, width: 44, height: 44)
        text.frame = NSRect(x: 16 + indent, y: y, width: inner + 4 - indent - 24, height: max(emote == nil ? 22 : 30, measured))
        y = text.frame.maxY + 6
        let statusHeight = height(status)
        status.frame = NSRect(x: 18, y: y, width: inner, height: statusHeight)
        if statusHeight > 0 { y += statusHeight + 4 }
        if !buttons.isEmpty {
            y += 10
            var x: CGFloat = 18
            for button in buttons {
                let w = button.intrinsicContentSize.width
                if x + w > 18 + inner, x > 18 { x = 18; y += 38 }
                button.frame = NSRect(x: x, y: y, width: w, height: 32)
                x += w + 8
            }
            y += 32
        }
        let copyWidth: CGFloat = 60 // fits "Copy" and "Copied"
        copyButton.isHidden = copyableText.isEmpty
        if !copyButton.isHidden {
            y += 4
            copyButton.frame = NSRect(x: width - 14 - copyWidth, y: y, width: copyWidth, height: 22)
            y += 22
        }
        let total = y + 12
        back.frame = NSRect(x: width - 66, y: 8, width: 28, height: 26)
        closeButton.frame = NSRect(x: width - 38, y: 8, width: 28, height: 26)

        // Beside Pip first, then above or below it, then the corners of the screen: the card must never cover the
        // place Pip is pointing at, then should stay off Pip and the input bar, and otherwise stay close to Pip.
        let size = CGSize(width: width, height: total)
        let candidates = [CGRect(x: anchor.minX - width - 8, y: anchor.minY, width: width, height: total),
                          CGRect(x: anchor.maxX + 8, y: anchor.minY, width: width, height: total),
                          CGRect(x: anchor.minX - width - 8, y: anchor.maxY - total, width: width, height: total),
                          CGRect(x: anchor.maxX + 8, y: anchor.maxY - total, width: width, height: total),
                          CGRect(x: anchor.midX - width / 2, y: anchor.minY - total - 8, width: width, height: total),
                          CGRect(x: anchor.midX - width / 2, y: anchor.maxY + 8, width: width, height: total),
                          CGRect(origin: CGPoint(x: work.minX + 8, y: work.minY + 8), size: size),
                          CGRect(origin: CGPoint(x: work.maxX - width - 8, y: work.minY + 8), size: size),
                          CGRect(origin: CGPoint(x: work.minX + 8, y: work.maxY - total - 8), size: size),
                          CGRect(origin: CGPoint(x: work.maxX - width - 8, y: work.maxY - total - 8), size: size)]
        let clamped = candidates.map { r -> CGRect in
            var r = r
            r.origin.x = min(max(r.minX, work.minX + 8), work.maxX - width - 8)
            r.origin.y = min(max(r.minY, work.minY + 8), work.maxY - total - 8)
            return r
        }
        let anchor = self.anchor, protectedTarget = self.protectedTarget, inputBounds = self.inputBounds
        func area(_ a: CGRect, _ b: CGRect?) -> CGFloat {
            guard let b else { return 0 }
            let i = a.intersection(b)
            return i.isNull ? 0 : i.width * i.height
        }
        func cost(_ r: CGRect) -> CGFloat {
            area(r, protectedTarget) * 100 + (area(r, anchor) + area(r, inputBounds)) * 4 + hypot(r.midX - anchor.midX, r.midY - anchor.midY)
        }
        let frame = clamped.enumerated().min { (cost($0.element), $0.offset) < (cost($1.element), $1.offset) }?.element ?? clamped[0]
        setFrame(ScreenSpace.toAppKit(frame), display: true)
    }

    // MARK: - Test hooks

    func sampleStep(selection line: String, areas: [String]) {
        go(to: 0)
        finishReveal()
        self.areas = []
        areasAtStepStart = []
        updateSelection(ExcelContext(sheet: "Budget", selection: areas.joined(separator: ","), activeCell: areas.last ?? "A1"), line: line)
        advanceTimer?.invalidate()
    }

}

private extension ReplyBubble.Page {
    var isStep: Bool {
        switch self {
        case .step: true
        default: false
        }
    }
}
