import AppKit
import CoachCore

/// How a lesson moves on by itself for CompanionController: a click on the circled place (with any keys the step says
/// to hold), typing into the focused box, or the app or website a step asks for coming to the front. Done stays for
/// everything else. Mirrors MainWindow.Lesson.cs.
extension CompanionController {
    func watchClicks() {
        clickWatch = ClickWatch()
        guard clickTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pollClick() } }
        RunLoop.main.add(timer, forMode: .common)
        clickTimer = timer
    }

    /// 20 times a second while Pip's card is up: a press on the circled place (with any keys the step says to hold)
    /// finishes a click step; twice a second during a typing step, whether the focused box got new text.
    func pollClick() {
        guard bubble.isShowing, !closed else { clickTimer?.invalidate(); clickTimer = nil; return }
        let down = NSEvent.pressedMouseButtons & 1 != 0
        let point = ScreenSpace.toTopLeft(NSRect(origin: NSEvent.mouseLocation, size: .zero)).origin
        let own = [window, inputWindow, bubble].filter(\.isVisible).map { ScreenSpace.toTopLeft($0.frame) }
        if clickWatch.pressed(down, at: point, target: lastTargetBounds, ignoring: own) {
            let flags = NSEvent.modifierFlags
            var held: Set<String> = []
            if flags.contains(.shift) { held.insert("shift") }
            if flags.contains(.command) { held.insert("command") }
            if flags.contains(.control) { held.insert("control") }
            if flags.contains(.option) { held.insert("option") }
            bubble.clickedTarget(held: held)
        }
        lessonTicks += 1
        if lessonTicks % 10 == 0 { checkGoal() }
        guard lessonTicks % 10 == 0, !readingTyping, let step = bubble.currentStep, ClickWatch.isTypingStep(step), DesktopAccessibility.isTrusted else { return }
        readingTyping = true
        Task {
            let value = await Task.detached(priority: .utility) { DesktopAccessibility.focusedTextFingerprint() }.value
            readingTyping = false
            guard bubble.currentStep == step else { return }
            if typingWatch.observe(value) { bubble.stepDone() }
        }
    }

    /// "Open your browser", "Go to chatgpt.com": done when that app or page is in front, checked twice a second
    /// from the app's name and its window title. Pip's own windows in front don't count either way.
    func checkGoal() {
        guard let step = bubble.currentStep, let goal = StepGoal.of(step, library: .shared) else { return }
        // While Pip itself is in front (the learner just typed a question), the app they were using counts.
        let pid: pid_t, name: String
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            (pid, name) = (front.processIdentifier, front.localizedName ?? "")
        } else if let last = capture.target() {
            (pid, name) = (last.pid, last.name)
        } else { return }
        let met = goal.isMet(app: name, title: ScreenCaptureService.windowTitle(of: pid))
        guard let atStart = goalAtStart else {
            goalAtStart = met
            if met { bubble.note("You’re already there. Press Done to go on.") }
            return
        }
        if met, !atStart { bubble.stepDone() }
    }
}
