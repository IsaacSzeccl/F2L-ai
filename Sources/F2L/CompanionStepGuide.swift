import AppKit
import CoachCore

/// A fresh look at the screen for every lesson step, for CompanionController. The answer to a question plans all the
/// steps from the one picture taken with it, but a click opens a menu, a page loads or another app comes to the front,
/// so the later steps' places were not on that picture. Each time a step is shown (after the learner finishes the
/// one before, "Show me again", "Start again"), F2L pictures the app as it is now and asks the AI where this step
/// happens and whether the screen is ready for it. Without a key, with sharing off, or if the request fails, the step
/// points where the first plan said, as before. The picture is dropped as soon as the reply is read.
extension CompanionController {
    static let lookingLine = "Looking at your screen…"

    func guideStep(_ number: Int) {
        stepGuideTask?.cancel()
        stepGuideTask = nil
        let planned = stepTargets.indices.contains(number) ? stepTargets[number] : nil
        // The first step is shown straight after the picture was taken for the question; that picture is still current.
        if number == 0, !firstStepSeen { firstStepSeen = true; point(at: planned, checkRequest: false); return }
        guard screenSharingEnabled, !testing, coach.isConfigured, lessonSteps.indices.contains(number),
              let app = capture.target() else { point(at: planned, checkRequest: false); return }
        let version = highlightVersion, steps = lessonSteps, goal = lessonGoal
        bubble.note(Self.lookingLine)
        stepGuideTask = Task { [weak self] in
            guard let self else { return }
            var shot: CapturedScreen?
            defer { shot?.jpeg.resetBytes(in: 0..<(shot?.jpeg.count ?? 0)) }
            var answer: StepGuide.Answer?
            shot = try? await capture.capture(app)
            if let shot, !Task.isCancelled {
                let names = await screenNames(shot)
                let jpeg = shot.jpeg, name = shot.app.name
                answer = await coach.guideStep(goal: goal, steps: steps, number: number, platform: "macOS", app: name,
                                               screenNames: names, jpeg: jpeg)
            }
            guard version == highlightVersion, !closed, !Task.isCancelled else { return }
            bubble.clearNote(Self.lookingLine)
            guard let shot, let answer else { point(at: planned, checkRequest: false); return }
            // Places are now measured against this picture, not the first one.
            replyCapture = CapturedScreen(jpeg: Data(), windowID: shot.windowID, frame: shot.frame, app: shot.app)
            // The AI saw the screen as it is: a place it didn't see is not drawn from the old plan's guess, only found by name.
            let target = answer.target ?? (planned ?? NamedPlace.target(in: steps[number])).map {
                ScreenTarget(left: 0, top: 0, right: 0, bottom: 0, label: $0.label, cell: $0.cell)
            }
            if stepTargets.indices.contains(number) { stepTargets[number] = target }
            if !answer.note.isEmpty { bubble.advice(answer.note) }
            point(at: target, checkRequest: false)
        }
    }
}
