import AppKit
import CoachCore

/// Finding a control a step names in a window as it is now, for `point(at:)` and the `--rehearse` check: the app's
/// own control names (Accessibility), the words read on screen, a match by meaning in any language, and a zoomed
/// second look by the AI. Nothing is drawn or said here; the caller does that with the result.
struct PlaceFinder {
    let coach: CoachClient
    /// Off for tests and the render check, which must not make AI requests.
    var askAI = true

    struct Result {
        var place: CGRect?
        var source = "none"
        /// The control now says the opposite of the step ("Close sidebar" for "Open Sidebar"): the step is done.
        var alreadyDone: String?
        /// The recipe's own advice when the step's name isn't on screen.
        var recipeHint: String?
    }

    /// `stillWanted` is checked after each AI request, so a superseded search stops early (`source` "superseded").
    static let browsers: Set<String> = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "company.thebrowser.Browser",
                                        "org.mozilla.firefox", "com.brave.Browser"]

    static func isBrowserControl(_ label: String) -> Bool {
        let words = TargetSnap.normalise(label)
        return ["address", "url", "new tab", "bookmark", "tab", "back", "forward", "reload", "extension"].contains { words.contains($0) }
    }

    func find(label: String, estimate: CGRect?, app: String, bundleID: String? = nil, pid: pid_t, window: CGRect, lines: [[ScreenWord]], picture: Data,
              step: String?, recipes: [Recipe], trusted: Bool, log: inout [String: Any],
              stillWanted: () -> Bool = { true }) async -> Result {
        var result = Result()
        var controls = trusted ? await Task.detached(operation: { DesktopAccessibility.controls(pid: pid, in: window) }).value : []
        var read = ScreenText.candidates(lines: lines)
        log["controls"] = controls.count
        // In a browser, a lesson is about the page: the tab titles and bookmarks ("Google Gemini") are left out, unless
        // the step is about the browser itself (the address bar, a new tab).
        if Self.browsers.contains(bundleID ?? ""), !Self.isBrowserControl(label),
           let page = trusted ? await Task.detached(operation: { DesktopAccessibility.largest(role: "AXWebArea", pid: pid, in: window) }).value : nil {
            controls = controls.filter { page.insetBy(dx: -4, dy: -4).contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            read = read.filter { page.insetBy(dx: -4, dy: -4).contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            log["page"] = PointingDiagnostics.rect(page)
        }
        // The step is already done when its switch now says the opposite ("Close sidebar" for "Open Sidebar"):
        // clicking it would undo what the learner wants.
        if !controls.contains(where: { TargetSnap.matches($0.name, TargetSnap.normalise(label)) }),
           let done = controls.first(where: { TargetSnap.alreadyDone(label: label, name: $0.name) }) {
            log["matched"] = done.name
            result.source = "already-done"; result.alreadyDone = done.name
            return result
        }
        if let snapped = TargetSnap.snap(box: estimate, label: label, candidates: controls) {
            result.place = snapped; result.source = "accessibility"
            log["matched"] = controls.first { $0.frame == snapped }?.name ?? ""
        } else if let snapped = TargetSnap.snap(box: estimate, label: label, candidates: read, byPosition: false) {
            result.place = snapped; result.source = "screen-text"
            log["matched"] = read.first { $0.frame == snapped }?.name ?? ""
        }
        // Not there by name: the app may be in another language, or call the control something else ("Open
        // Sidebar" against 開啟側邊欄 or "Main menu"). Ask the AI which name on screen is the same control (text only).
        if result.place == nil, !TargetSnap.isGeneric(label), askAI, coach.isConfigured {
            let named = controls.filter { TargetSnap.sensible($0.frame) }
            let words = read.filter { TargetSnap.sensible($0.frame) && $0.name.split(separator: " ").count <= 3 }
            if let name = await coach.matchName(label: label, step: step, app: app, names: named.map(\.name) + words.map(\.name)) {
                guard stillWanted() else { result.source = "superseded"; return result }
                if let hit = named.first(where: { $0.name == name }) ?? words.first(where: { $0.name == name }) {
                    result.place = hit.frame; result.source = named.contains(hit) ? "meaning+accessibility" : "meaning+screen-text"
                    log["matched"] = name
                }
            }
        }
        // A recipe step whose on-screen name is not there: the interface may have moved on, so the caller says what
        // the recipe says to try instead of letting the learner follow a circle drawn around a guess.
        if result.place == nil, let hint = RecipeScreen.hint(forLabel: label, in: recipes) {
            log["recipeHint"] = true
            result.recipeHint = hint
        }
        // Not confirmed on screen (an icon with no visible name, or another app): a zoomed second look by the AI
        // around its first guess, or across the whole window when there is none. One short extra request.
        if result.place == nil, !picture.isEmpty, !TargetSnap.isGeneric(label), askAI, coach.isConfigured {
            let crop = ZoomLocate.crop(around: estimate, window: window), shot = picture
            if let piece = await Task.detached(operation: { ScreenCaptureService.cropJPEG(shot, window: window, to: crop) }).value,
               let found = await coach.zoomLocate(label: label, app: app, jpeg: piece, crop: crop) {
                guard stillWanted() else { result.source = "superseded"; return result }
                log["zoomBox"] = PointingDiagnostics.rect(found)
                // Knowing where to look, a real control under the zoomed box makes it exact.
                if let snapped = TargetSnap.snap(box: found, label: "", candidates: controls) {
                    result.place = snapped; result.source = "zoom+accessibility"
                } else {
                    result.place = found; result.source = "model-zoom"
                }
            }
        }
        // A typing step is about a box: circle the box, not its label ("In 說明, type: …" circled the word 說明).
        if let step, ClickWatch.isTypingStep(step), trusted, result.alreadyDone == nil {
            let boxes = await Task.detached(operation: { DesktopAccessibility.textBoxes(pid: pid, in: window) }).value
            if let box = Self.box(for: result.place, estimate: estimate, in: boxes) {
                log["textBox"] = PointingDiagnostics.rect(box)
                result.source = result.place == nil ? "text-box" : "text-box via \(result.source)" // a real box: confirmed
                result.place = box
            }
        }
        return result
    }

    /// The text box the step means: the one its label sits on or just above (within 90 points, overlapping
    /// sideways), else the one under the middle of the AI's box. Nil when neither is clear.
    static func box(for label: CGRect?, estimate: CGRect?, in boxes: [CGRect]) -> CGRect? {
        if let label {
            if let inside = boxes.filter({ $0.contains(CGPoint(x: label.midX, y: label.midY)) }).min(by: { $0.width * $0.height < $1.width * $1.height }) {
                return inside
            }
            let below = boxes.filter { $0.minY >= label.minY - 4 && $0.minY - label.maxY <= 90 && $0.maxX > label.minX && $0.minX < label.maxX + 200 }
            if let nearest = below.min(by: { $0.minY - label.maxY < $1.minY - label.maxY }) { return nearest }
        }
        if let estimate {
            return boxes.filter { $0.contains(CGPoint(x: estimate.midX, y: estimate.midY)) }.min { $0.width * $0.height < $1.width * $1.height }
        }
        return nil
    }
}
