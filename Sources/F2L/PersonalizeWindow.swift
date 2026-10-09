import AppKit
import CoachCore

/// An optional, keyboard-accessible welcome conversation. The same steps and profile schema exist on Windows.
@MainActor
final class PersonalizeWindow: NSWindow, NSWindowDelegate, NSTextFieldDelegate {
    private static let cream = Palette.hex(0xFAF8F3), sage = Palette.hex(0xE8EEE5), green = Palette.hex(0x345D50)
    private static let muted = Palette.hex(0x69736D)
    private let root = FlippedView()
    private let body = FlippedView()
    private let scroll = NSScrollView()
    private let store: ProfileStore
    private let coach: CoachClient
    private var original: ProfileDocument
    private var profile: LearnerProfile
    private var plan: StarterPlan?
    private var step = 0
    private var renderedStep = -1
    private var busy = false, finished = false
    private var errorMessage = ""
    private var request: Task<Void, Never>?
    private var nameField: NSTextField?, roleField: NSTextField?, goalField: NSTextField?, learnField: NSTextField?
    private var primary: FlatButton?
    var onDone: (() -> Void)?
    /// What they want to learn changed and was saved straight away (their profile already existed), so Pip uses it now.
    var onChange: (() -> Void)?
    var onSettings: (() -> Void)?

    init(store: ProfileStore = ProfileStore(), coach: CoachClient = CoachClient()) {
        self.store = store; self.coach = coach
        original = store.load(); profile = original.profile ?? LearnerProfile(); plan = original.plan
        let work = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 900)
        super.init(contentRect: NSRect(x: 0, y: 0, width: min(960, work.width - 48), height: min(680, work.height - 64)),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = original.profile == nil ? "Welcome to F2L" : "Your learning with Pip"
        backgroundColor = Self.cream
        appearance = NSAppearance(named: .aqua)
        root.wantsLayer = true
        root.layer?.backgroundColor = Self.cream.cgColor
        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        delegate = self
        contentView = root
        step = original.profile != nil && plan != nil ? 2 : 0
        rebuild()
        center()
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 13,
                       color: NSColor = Palette.ink, weight: NSFont.Weight = .regular, in parent: NSView? = nil) -> CGFloat {
        let field = makeLabel(text, size: size, weight: weight, color: color, wraps: true)
        let height = ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 2000)).height ?? 20)
        field.frame = NSRect(x: x, y: y, width: width, height: height)
        (parent ?? body).addSubview(field)
        return height
    }

    /// Pill-shaped buttons: the whole welcome is round, like Pip.
    @discardableResult
    private func button(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 40,
                        selected: Bool = false, in parent: NSView? = nil, action: @escaping () -> Void) -> FlatButton {
        let button = FlatButton(text, size: 13, ink: selected ? .white : Self.green, fill: selected ? Self.green : Self.sage)
        button.frame = NSRect(x: x, y: y, width: width, height: height)
        button.cornerRadius = height / 2; button.onClick = action
        if selected { button.weight = .semibold }
        button.focusRingType = .exterior
        button.setAccessibilityLabel(text)
        (parent ?? body).addSubview(button)
        return button
    }

    /// A pill-shaped text field with its question above it.
    private func input(_ value: String, placeholder: String, label title: String, y: CGFloat, width: CGFloat, height: CGFloat = 48) -> NSTextField {
        _ = label(title, x: 6, y: y, width: width, size: 13, color: Palette.ink, weight: .semibold)
        let field = NSTextField(string: value)
        field.placeholderString = placeholder; field.font = Fonts.inter(15)
        field.textColor = Palette.ink; field.drawsBackground = false; field.isBordered = false
        field.focusRingType = .none; field.delegate = self
        field.lineBreakMode = .byTruncatingTail
        let box = RoundedBox(fill: .white, radius: height / 2, border: Palette.hex(0xD8DFD5))
        box.frame = NSRect(x: 0, y: y + 26, width: width, height: height)
        body.addSubview(box)
        field.frame = NSRect(x: 22, y: y + 26 + (height - 22) / 2, width: width - 44, height: 22)
        field.setAccessibilityLabel(title)
        body.addSubview(field)
        return field
    }

    private func circle(_ diameter: CGFloat, fill: NSColor, at origin: NSPoint, in parent: NSView, border: NSColor? = nil) -> RoundedBox {
        let dot = RoundedBox(fill: fill, radius: diameter / 2, border: border)
        dot.frame = NSRect(origin: origin, size: NSSize(width: diameter, height: diameter))
        parent.addSubview(dot)
        return dot
    }

    private func rebuild() {
        let offset = renderedStep == step ? scroll.contentView.bounds.origin : .zero
        renderedStep = step
        root.subviews.forEach { $0.removeFromSuperview() }
        body.subviews.forEach { $0.removeFromSuperview() }
        nameField = nil; roleField = nil; goalField = nil; learnField = nil; primary = nil
        let w = root.bounds.width, h = root.bounds.height, side: CGFloat = 300, contentWidth = w - side - 80

        // Left: a soft round panel with Pip in a big circle.
        let panel = RoundedBox(fill: Self.sage, radius: 36)
        panel.frame = NSRect(x: 20, y: 20, width: side - 20, height: h - 40)
        root.addSubview(panel)
        _ = label("F2L  ·  PIP", x: 30, y: 30, width: 220, size: 10, color: Self.green, weight: .semibold, in: panel)
        _ = label(["Your work,\nyour way.", "Your pace.\nNo pressure.", "Small steps.\nReal progress."][step],
                  x: 30, y: 62, width: 220, size: 27, color: Self.green, weight: .semibold, in: panel)
        let disc = side - 20 - 48
        let discY = max(190, min(h - 40 - disc - 110, 200))
        let halo = circle(disc, fill: Self.cream.withAlphaComponent(0.9), at: NSPoint(x: 24, y: discY), in: panel)
        if let url = Assets.url("Pip/welcome-journey.png"), let image = NSImage(contentsOf: url) {
            let art = NSImageView(frame: halo.bounds.insetBy(dx: 6, dy: 6))
            art.image = image; art.imageScaling = .scaleProportionallyUpOrDown
            art.setAccessibilityElement(false)
            halo.addSubview(art)
        } else {
            let pip = PipView(frame: halo.bounds.insetBy(dx: 30, dy: 20))
            pip.setReducedMotion(true); pip.setWaving(true); halo.addSubview(pip)
        }
        _ = label("“One useful thing at a time.”", x: 30, y: h - 40 - 62, width: 220, size: 14, color: Self.green, in: panel)

        // Top: three numbered circles joined by a line.
        let titles = ["Your work", "Your AI", "Your plan"]
        let stepWidth = contentWidth / 3
        for (index, title) in titles.enumerated() {
            let x = side + 40 + CGFloat(index) * stepWidth
            if index < titles.count - 1 {
                let line = RoundedBox(fill: index < step ? Self.green : Palette.hex(0xDEE3DC), radius: 1.5)
                line.frame = NSRect(x: x + 34, y: 41, width: stepWidth - 40, height: 3)
                root.addSubview(line)
            }
            let done = index < step, current = index == step
            let dot = circle(28, fill: done || current ? Self.green : .white, at: NSPoint(x: x, y: 28), in: root,
                             border: done || current ? nil : Palette.hex(0xCFD8CC))
            _ = label(done ? "✓" : "\(index + 1)", x: 0, y: 5, width: 28, size: 12, color: done || current ? .white : Self.muted,
                      weight: .semibold, in: dot)
            (dot.subviews.last as? NSTextField)?.alignment = .center
            let name = makeLabel(title, size: 11, weight: current ? .semibold : .regular, color: current ? Self.green : Self.muted)
            name.alignment = .center
            name.frame = NSRect(x: x - 36, y: 62, width: 100, height: 16)
            root.addSubview(name)
        }

        scroll.frame = NSRect(x: side + 40, y: 96, width: contentWidth + 12, height: h - 96 - 90)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        body.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 500)
        scroll.documentView = body; root.addSubview(scroll)
        var height: CGFloat
        switch step {
        case 0: height = world(width: contentWidth)
        case 1: height = pace(width: contentWidth)
        default: height = path(width: contentWidth)
        }
        if !errorMessage.isEmpty {
            height += 18
            height += label(errorMessage, x: 0, y: height, width: contentWidth, size: 12, color: Palette.hex(0x944C32))
        }
        body.setFrameSize(NSSize(width: contentWidth, height: max(scroll.bounds.height, height + 24)))
        body.scroll(offset)
        if busy { body.subviews.forEach { ($0 as? NSControl)?.isEnabled = false } }
        if !errorMessage.isEmpty { body.scroll(NSPoint(x: 0, y: max(0, body.bounds.height - scroll.bounds.height))) }

        // Bottom: back on the left, the next step on the right.
        let bottom = h - 70
        if step > 0 {
            let back = button(step == 2 ? "Edit my answers" : "Back", x: side + 40, y: bottom, width: 140, in: root) { [weak self] in
                guard let self else { return }; captureFields(); request?.cancel(); busy = false; step = max(0, step - 1); errorMessage = ""; rebuild()
            }
            back.isEnabled = !busy
        } else {
            button(original.profile == nil ? "Not now" : "Cancel", x: side + 40, y: bottom, width: 120, in: root) { [weak self] in self?.performClose(nil) }
        }
        if step == 1 {
            let local = button("Plan without AI", x: w - 372, y: bottom, width: 150, in: root) { [weak self] in self?.makePlan(usingAI: false) }
            local.isEnabled = !busy
        }
        primary = button(step == 0 ? "Next" : step == 1 ? (busy ? "Making your plan…" : "Make my plan") : "Save & meet Pip",
                         x: w - 212, y: bottom, width: 172, selected: true, in: root) { [weak self] in self?.next() }
        primary?.isEnabled = !busy && (step != 0 || profile.isReady)
        primary?.keyEquivalent = "\r"
        if original.profile != nil {
            let forget = button("Forget my profile", x: side + 40, y: h - 24, width: 130, height: 20, in: root) { [weak self] in self?.forget() }
            forget.fill = nil; forget.textSize = 10
        }
    }

    private func world(width: CGFloat) -> CGFloat {
        var y = label(profile.name.isEmpty ? "Tell Pip about your work." : "Tell Pip about your work, \(profile.name).",
                      x: 0, y: 0, width: width, size: 26, weight: .semibold) + 10
        y += label("Pip uses this to fit every answer to your job. Type it your way; there are no wrong answers.",
                   x: 0, y: y, width: width, color: Self.muted) + 26
        nameField = input(profile.name, placeholder: "Your first name (optional)", label: "What should Pip call you?", y: y, width: width); y += 94
        roleField = input(profile.role, placeholder: "e.g. Operations coordinator at a logistics company", label: "What do you do at work?", y: y, width: width); y += 94
        goalField = input(profile.goal, placeholder: "e.g. Weekly sales reports in Excel take me hours",
                          label: "What would you like help with at work?", y: y, width: width)
        return y + 90
    }

    private func pace(width: CGFloat) -> CGFloat {
        var y = label("How do you use AI today?", x: 0, y: 0, width: width, size: 26, weight: .semibold) + 10
        y += label("Pip changes how much it explains. Every starting point is fine.", x: 0, y: y, width: width, color: Self.muted) + 24
        // Three round cards, each with Pip's emote in a circle.
        let gap: CGFloat = 12, cardWidth = (width - gap * 2) / 3, cardHeight: CGFloat = 196
        for (index, option) in LearnerProfile.experiences.enumerated() {
            let selected = profile.experience == option.0
            let card = RoundedBox(fill: selected ? Palette.hex(0xF1F6EF) : .white, radius: 28,
                                  border: selected ? Self.green : Palette.hex(0xE0E5DE))
            card.frame = NSRect(x: CGFloat(index) * (cardWidth + gap), y: y, width: cardWidth, height: cardHeight)
            body.addSubview(card)
            let halo = circle(72, fill: selected ? Self.sage : Self.cream, at: NSPoint(x: (cardWidth - 72) / 2, y: 18), in: card)
            let emote = NSImageView(frame: halo.bounds.insetBy(dx: 6, dy: 6))
            emote.image = (option.0 == "new" ? PipEmote.curious : option.0 == "some" ? .happy : .hello).image(side: 60)
            emote.setAccessibilityElement(false)
            halo.addSubview(emote)
            let title = makeLabel(option.1, size: 14, weight: .semibold, color: selected ? Self.green : Palette.ink, wraps: true)
            title.alignment = .center
            title.frame = NSRect(x: 12, y: 102, width: cardWidth - 24, height: 22)
            card.addSubview(title)
            let detail = makeLabel(option.2, size: 12, color: Self.muted, wraps: true)
            detail.alignment = .center
            detail.frame = NSRect(x: 14, y: 128, width: cardWidth - 28, height: 52)
            card.addSubview(detail)
            let tap = FlatButton(" ", size: 1, fill: nil) // a title of at least one character keeps FlatButton drawing safe
            tap.frame = card.bounds
            tap.setAccessibilityLabel(option.1)
            tap.onClick = { [weak self] in self?.captureFields(); self?.profile.experience = option.0; self?.rebuild() }
            card.addSubview(tap)
        }
        y += cardHeight + 30
        y += label("Tools you already use at work · optional", x: 6, y: y, width: width, size: 13, weight: .semibold) + 12
        let chip: CGFloat = (width - 16) / 3
        for (index, tool) in ToolCatalog.all.enumerated() {
            button(tool.name, x: CGFloat(index % 3) * (chip + 8), y: y + CGFloat(index / 3) * 46, width: chip, height: 38,
                   selected: profile.existingTools.contains(tool.id)) { [weak self] in
                guard let self else { return }
                if profile.existingTools.contains(tool.id) { profile.existingTools.removeAll { $0 == tool.id } } else { profile.existingTools.append(tool.id) }
                rebuild()
            }
        }
        y += 100
        let toggle = NSButton(checkboxWithTitle: "Use this to personalise Pip’s help", target: self, action: #selector(togglePersonalization))
        toggle.state = profile.personalizationEnabled ? .on : .off; toggle.font = Fonts.inter(13)
        toggle.frame = NSRect(x: 2, y: y, width: width, height: 24); body.addSubview(toggle); y += 32
        return y + label("Saved only on this computer. Make my plan sends your role, work goal, AI level and tools (never your name or screen) to \(coach.provider.name). Plan without AI stays on this computer.",
                         x: 2, y: y, width: width, size: 11, color: Self.muted)
    }

    private func path(width: CGFloat) -> CGFloat {
        let plan = plan ?? StarterPlan.draft(for: profile)
        var y = learning(width: width, plan: plan)
        y += label(plan.source == "local" ? "YOUR STARTER DRAFT · MADE ON THIS DEVICE" : "YOUR PERSONAL PLAN · WITH \(plan.source.uppercased())", x: 0, y: y, width: width - 64, size: 10, color: Self.green, weight: .semibold) + 13
        let cheer = NSImageView(frame: NSRect(x: width - 56, y: y - 32, width: 56, height: 56))
        cheer.image = PipEmote.cheer.image(side: 56)
        cheer.setAccessibilityElement(false)
        body.addSubview(cheer)
        y += label(plan.title, x: 0, y: y, width: width - 64, size: 25, weight: .semibold) + 12
        y += label(plan.summary, x: 0, y: y, width: width, color: Self.muted) + 22
        y += label("A SMALL TOOLKIT, CHOSEN FOR YOU", x: 0, y: y, width: width, size: 11, color: Self.green, weight: .semibold) + 15
        for suggestion in plan.tools {
            guard let tool = ToolCatalog.find(suggestion.id) else { continue }
            let box = RoundedBox(fill: .white, radius: 26, border: Palette.hex(0xE0E5DE))
            let height = max(88, 44 + labelHeight(suggestion.reason, width: width - 134))
            box.frame = NSRect(x: 0, y: y, width: width, height: height)
            body.addSubview(box)
            _ = label(tool.name, x: 24, y: 15, width: width - 150, size: 14, weight: .semibold, in: box)
            _ = label(suggestion.reason, x: 24, y: 39, width: width - 150, size: 12, color: Self.muted, in: box)
            button("Explore", x: width - 106, y: (height - 34) / 2, width: 86, height: 34, in: box) { if let url = URL(string: tool.url) { NSWorkspace.shared.open(url) } }
            y += height + 10
        }
        y += label("Start with tools your workplace already approves. Features and access depend on your plan. These are suggestions, not connected accounts.", x: 0, y: y, width: width, size: 11, color: Self.muted) + 24
        y += label("A WORKFLOW TO TRY", x: 0, y: y, width: width, size: 11, color: Self.green, weight: .semibold) + 18
        for (index, item) in plan.workflow.enumerated() {
            let badge = RoundedBox(fill: Self.sage, radius: 15); badge.frame = NSRect(x: 0, y: y, width: 30, height: 30); body.addSubview(badge)
            _ = label("\(index + 1)", x: 10, y: 6, width: 18, size: 13, color: Self.green, weight: .semibold, in: badge)
            let titleHeight = label(item.title, x: 44, y: y, width: width - 44, size: 14, weight: .medium)
            y += titleHeight + 6
            y += label(item.detail, x: 44, y: y, width: width - 44, size: 12, color: Self.muted) + 20
        }
        let refresh = button(busy ? "Making your plan…" : "Refresh with AI", x: 0, y: y, width: 153) { [weak self] in self?.makePlan(usingAI: true) }
        refresh.isEnabled = !busy
        if !coach.isConfigured {
            button("Set up AI in Settings", x: 163, y: y, width: 188) { [weak self] in self?.onSettings?() }
        }
        y += 52
        return y + label("You can come back here any time from My learning & profile in Pip’s ··· menu.", x: 0, y: y, width: width, size: 11, color: Self.muted)
    }

    /// What they want to learn: Pip's ideas as round chips to tick, and a field for their own. Pip offers the ticked
    /// ones when it opens, and nothing starts until they pick one.
    private func learning(width: CGFloat, plan: StarterPlan) -> CGFloat {
        var y = label("What do you want to learn?", x: 0, y: 0, width: width - 64, size: 25, weight: .semibold) + 8
        y += label("Pick up to \(LearnerProfile.maxLearning), or add your own. Pip offers these when it opens; nothing starts until you choose.",
                   x: 0, y: y, width: width, color: Self.muted) + 18
        let ideas = LearnerProfile.learningIdeas(for: profile, plan: plan)
        let chip = (width - 10) / 2
        for (index, idea) in ideas.enumerated() {
            let chosen = profile.learning.contains(idea)
            let pick = button(idea, x: CGFloat(index % 2) * (chip + 10), y: y + CGFloat(index / 2) * 46, width: chip, height: 38,
                              selected: chosen) { [weak self] in self?.toggleLearning(idea) }
            pick.isEnabled = chosen || profile.learning.count < LearnerProfile.maxLearning
        }
        y += CGFloat((ideas.count + 1) / 2) * 46 + 8
        let field = NSTextField(string: "")
        field.placeholderString = "Something else you want to learn"; field.font = Fonts.inter(14)
        field.textColor = Palette.ink; field.drawsBackground = false; field.isBordered = false
        field.focusRingType = .none; field.delegate = self
        field.setAccessibilityLabel("Something else you want to learn")
        let box = RoundedBox(fill: .white, radius: 22, border: Palette.hex(0xD8DFD5))
        box.frame = NSRect(x: 0, y: y, width: width - 106, height: 44)
        body.addSubview(box)
        field.frame = NSRect(x: 20, y: y + 11, width: width - 146, height: 22)
        body.addSubview(field)
        learnField = field
        button("Add", x: width - 96, y: y + 2, width: 96, height: 40) { [weak self] in self?.addLearning() }
        return y + 44 + 34
    }

    private func toggleLearning(_ topic: String) {
        captureFields()
        if profile.learning.contains(topic) { profile.learning.removeAll { $0 == topic } } else { profile.learning.append(topic) }
        learningChanged()
    }

    private func addLearning() {
        guard let topic = learnField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty else { return }
        captureFields()
        profile.learning.append(topic)
        learningChanged()
    }

    /// Saved straight away once they have a profile, so Pip's next answer already knows.
    private func learningChanged() {
        profile = profile.normalized
        if original.profile != nil, !busy {
            let saved = ProfileDocument(profile: profile, plan: plan ?? original.plan ?? StarterPlan.draft(for: profile), onboardingComplete: true)
            do { try store.save(saved); original = saved; onChange?() }
            catch { errorMessage = "Your choice couldn’t be saved. Check that this computer’s F2L folder is writable, then try again." }
        }
        rebuild()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === learnField, selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        addLearning()
        return true
    }

    private func labelHeight(_ text: String, width: CGFloat) -> CGFloat {
        let field = makeLabel(text, size: 12, color: Self.muted, wraps: true)
        return ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 2000)).height ?? 40)
    }
    private func captureFields() {
        if let field = nameField { profile.name = field.stringValue }
        if let field = roleField { profile.role = field.stringValue }
        if let field = goalField { profile.goal = field.stringValue }
        // The kind of help comes from what they typed, so there is nothing extra to pick.
        profile.focus = LearnerProfile.inferFocus(role: profile.role, goal: profile.goal)
        profile = profile.normalized
    }
    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) !== learnField else { return }
        captureFields(); primary?.isEnabled = profile.isReady
    }
    @objc private func togglePersonalization(_ sender: NSButton) { profile.personalizationEnabled = sender.state == .on }
    private func next() {
        captureFields()
        if step == 0 { guard profile.isReady else { return }; step = 1; errorMessage = ""; rebuild() }
        else if step == 1 { makePlan(usingAI: true) }
        else { save() }
    }
    private func makePlan(usingAI: Bool) {
        guard !busy else { return }
        captureFields(); plan = StarterPlan.draft(for: profile); errorMessage = ""
        guard usingAI, coach.isConfigured else {
            if usingAI { errorMessage = "Your AI isn’t connected yet, so Pip made a starter draft on this device. Save it now, or set up AI and refresh it." }
            step = 2; rebuild(); return
        }
        busy = true; rebuild()
        let snapshot = profile
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await coach.starterPlan(for: snapshot)
                guard !Task.isCancelled, !finished else { return }
                plan = result
            } catch {
                guard !Task.isCancelled, !finished else { return }
                errorMessage = (error as? CoachRequestError)?.message ?? "The AI plan isn’t available right now. You can keep this starter draft and try again later."
            }
            busy = false; step = 2; rebuild()
        }
    }
    private func save() {
        guard !busy else { return }
        captureFields()
        let plan = plan ?? StarterPlan.draft(for: profile)
        do {
            try store.save(ProfileDocument(profile: profile, plan: plan, onboardingComplete: true))
            finished = true; close(); onDone?()
        } catch { errorMessage = "Your profile couldn’t be saved. Check that this computer’s F2L folder is writable, then try again."; rebuild() }
    }
    private func forget() {
        let alert = NSAlert(); alert.messageText = "Forget your profile and starter plan?"
        alert.informativeText = "Pip will stop adding this background to new questions. Earlier conversations and information already sent to an AI provider are not erased."
        alert.addButton(withTitle: "Forget profile"); alert.addButton(withTitle: "Keep it")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try store.forget(); finished = true; request?.cancel(); close(); onDone?() }
        catch { errorMessage = "Your profile couldn’t be removed. Please try again."; rebuild() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !finished {
            do {
                original.onboardingComplete = true
                try store.save(original)
            } catch { errorMessage = "Pip couldn’t save your choice. Please try again."; rebuild(); return false }
        }
        request?.cancel(); finished = true
        onDone?()
        return true
    }
    func windowWillClose(_ notification: Notification) { request?.cancel() }

    /// Draw the actual UI with a synthetic profile, without network or production profile writes.
    func preview(step: Int, profile: LearnerProfile, plan: StarterPlan? = nil) {
        self.step = step; self.profile = profile; self.plan = plan ?? StarterPlan.draft(for: profile); rebuild()
    }
}
