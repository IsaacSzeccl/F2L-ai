import AppKit
@preconcurrency import ApplicationServices
import CoachCore

/// Follows the control the coach circled: keeps the circle on it as the page scrolls or the window moves,
/// and reports when the learner types into it, sends it, or clicks it (proactive nudges).
@MainActor
final class TargetWatcher {
    var onEvent: ((StepEvent) -> Void)?
    var onFrameChanged: ((CGRect) -> Void)?
    var onTargetLost: (() -> Void)?

    private let reader: AccessibilityReader
    private var element: AXUIElement?
    private var tracker: StepTracker?
    private var lastFrame: CGRect?
    private var timer: Timer?
    private var clickMonitor: Any?
    private var polling = false
    private var failedReads = 0

    init(reader: AccessibilityReader) {
        self.reader = reader
    }

    func watch(element: AXUIElement, annotation: Annotation, label: String, initialValue: String) {
        stop()
        self.element = element
        self.failedReads = 0
        self.lastFrame = annotation.rect
        self.tracker = StepTracker(label: label, role: annotation.elementRole ?? "", frame: annotation.rect, initialValue: initialValue)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let location = NSEvent.mouseLocation
            let point = CGPoint(x: location.x, y: NSScreen.primaryHeight - location.y)
            Task { @MainActor in self?.handleClick(at: point) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        element = nil
        tracker = nil
        lastFrame = nil
    }

    private func poll() async {
        guard let element, !polling else { return }
        polling = true
        defer { polling = false }
        let state = await reader.state(of: element)
        guard self.element === element else { return } // retargeted while we waited
        guard let frame = state.frame, frame.width > 0 else {
            // A busy app can time out one read; only drop the circle when the control is really gone.
            failedReads += 1
            if state.gone || failedReads >= 4 {
                stop()
                onTargetLost?()
            }
            return
        }
        failedReads = 0
        let value = state.value
        if frame != lastFrame {
            lastFrame = frame
            tracker?.move(to: frame)
            onFrameChanged?(frame)
        }
        let now = Date()
        if let value, let event = tracker?.observe(value: value, at: now) { emit(event) }
        if let event = tracker?.tick(at: now) { emit(event) }
    }

    private func handleClick(at point: CGPoint) {
        if let event = tracker?.observeClick(at: point) { emit(event) }
    }

    private func emit(_ event: StepEvent) {
        if tracker?.isFinished == true {
            let handler = onEvent
            stop()
            handler?(event)
        } else {
            onEvent?(event)
        }
    }
}
