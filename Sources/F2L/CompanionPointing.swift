import AppKit
import CoachCore

/// Circling places on screen for CompanionController: where a reply or lesson step happens (Excel cells, controls
/// found by name through Accessibility, words read on screen, a zoomed second look by the AI), keeping the circle on
/// the place while the window moves, and the optional walking Pip beside it. Mirrors MainWindow.Pointing.cs.
extension CompanionController {
    var panelRect: CGRect? {
        guard panelOpen, inputWindow.isVisible else { return nil }
        return ScreenSpace.toTopLeft(inputWindow.frame)
    }

    /// Sends Pip to where the reply or step happens and circles it, found on the screen as it is now:
    /// - the window is pictured again and its words are read on this Mac (Apple Vision), so a button or tab is circled
    ///   where its name appears, and an Excel cell where its column letter and row number meet;
    /// - Accessibility's named controls are used too, and Excel's own confirmation where it gives one (Windows).
    /// The model's rough position is shown dashed at once, and replaced by a checked place when one is found.
    /// Every decision is written to pointing.log for debugging.
    func point(at target: ScreenTarget?, checkRequest: Bool) {
        guard let target, var captured = replyCapture, screenSharingEnabled else { return }
        var cell = target.cell.flatMap(CellReference.parse)
        // A later step can happen in another app (the browser, after "Open your browser"): look for it there, by name,
        // since the AI's position belongs to the earlier screenshot.
        var sameApp = true
        if cell == nil, let now = capture.target(), now.pid != captured.app.pid, let located = try? capture.locate(now) {
            captured = located; sameApp = false
        }
        // In Excel a label such as "A1" is a cell even when the AI left out "cell": find it from the headings, not the
        // name box that also shows "A1".
        if cell == nil, captured.app.isExcel, let parsed = CellReference.parse(target.label) { cell = parsed }
        // A direct "circle A1" can't be quietly answered with B1.
        if checkRequest, let cell, requestedCells.count == 1, !CellReference.matchesRequest(cell, requestedCells) { return }
        let version = highlightVersion
        let estimate = sameApp && target.hasBox ? CompanionPlacement.fromScreenshot(window: captured.frame, target: target) : nil
        var log: [String: Any] = ["label": target.label, "cell": target.cell ?? "", "window": PointingDiagnostics.rect(captured.frame) ?? [:],
                                  "modelBox": PointingDiagnostics.rect(estimate) ?? [:], "app": captured.app.name]
        Task {
            defer { PointingDiagnostics.record(log) }
            // The window picture is kept only until this place is found (a zoomed second look may need it).
            var picture = Data()
            defer { picture.resetBytes(in: 0..<picture.count) }
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
                picture = jpeg
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
                } else if trusted, now.app.isExcel, !picture.isEmpty,
                          let grid = await Task.detached(operation: { DesktopAccessibility.largest(role: "AXLayoutArea", pid: pid, in: window) }).value,
                          let found = await Task.detached(operation: { [picture] in
                              ExcelGridReader.place(range, jpeg: picture, window: window, grid: grid, words: words) }).value {
                    // The column letters weren't readable: the gridlines in the same picture place the cell.
                    place = found; source = "excel-gridlines"
                } else if trusted, now.app.isExcel, let metrics = await selectionReader.cellMetrics(range),
                          let grid = await Task.detached(operation: { DesktopAccessibility.largest(role: "AXLayoutArea", pid: pid, in: window) }).value,
                          let measured = ExcelGeometry.choose(ExcelGeometry.candidates(metrics, grid: grid), near: estimate) {
                    place = measured; source = "excel-measured"
                }
            } else {
                let finder = PlaceFinder(coach: coach, askAI: !testing)
                let found = await finder.find(label: target.label, estimate: estimate, app: now.app.name, bundleID: now.app.bundleID, pid: pid, window: window,
                                              lines: lines, picture: picture, step: bubble.currentStep, recipes: turnRecipes,
                                              trusted: trusted, log: &log,
                                              stillWanted: { [weak self] in version == self?.highlightVersion && self?.closed == false })
                guard found.source != "superseded" else { log["source"] = "superseded"; return }
                if let done = found.alreadyDone {
                    log["source"] = "already-done"
                    guard version == highlightVersion, !closed else { return }
                    clearHighlight() // the dashed first guess, if one was drawn
                    bubble.alreadyDone("Already done: it shows \(done) now, so skip this one.")
                    return
                }
                if let hint = found.recipeHint { bubble.advice(hint) }
                place = found.place; source = found.source
            }
            // Nothing on screen could confirm it (an icon with no visible name, and no Accessibility): still go to where
            // the model saw it, dashed so it reads as approximate, and say how to make it exact.
            if place == nil, let estimate {
                place = estimate
                source = "model-estimate"
                if !trusted, cell == nil, !shownAccessibilityTip {
                    shownAccessibilityTip = true
                    bubble.tip("Approximate. Turn on F2L under Accessibility so I can find icons exactly. Already on? Use Reset permissions in Settings.",
                               action: "Settings") { self.showSettings() }
                }
            }
            log["source"] = source
            log["drawn"] = PointingDiagnostics.rect(place)
            guard version == highlightVersion, !closed, let place else { if version != highlightVersion { log["source"] = "superseded" }; return }
            replyCapture = now
            showTarget(now, place, verified: !source.hasPrefix("model"), cell: nil, sheet: nil, persistent: true)
        }
    }

    func forgetPlaces() {
        stepGuideTask?.cancel()
        stepGuideTask = nil
        lessonGoal = ""
        lessonSteps = []
        replyCapture = nil
        replyTarget = nil
        stepTargets = []
        turnRecipes = []
        requestedCells = []
    }

    func showTarget(_ captured: CapturedScreen, _ bounds: CGRect, verified: Bool, cell: CellReference?, sheet: String?, persistent: Bool = false) {
        guard CompanionPlacement.isUsable(bounds), ScreenCaptureService.isCurrent(captured),
              ScreenCaptureService.pointBelongsToWindow(captured.windowID, CGPoint(x: bounds.midX, y: bounds.midY)) else { return }
        targetPersistent = persistent
        targetCapture = captured
        targetCell = cell
        targetSheet = sheet
        targetShown = Date()
        if guide == nil { guide = GuideOverlayWindow() }
        guide?.show(bounds, verified: verified)
        watchClicks()
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
    func watchTarget() {
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

    func clearHighlight() {
        highlightVersion += 1
        stepGuideTask?.cancel()
        stepGuideTask = nil
        guide?.close()
        guide = nil
        stopTeachingCompanion()
        lastTargetBounds = nil
        targetCapture = nil
        targetCell = nil
        targetSheet = nil
        if inputDodging { inputDodging = false; layoutInputBar() }
    }

    func updateTeachingCompanion(_ target: CGRect) {
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

    func stopTeachingCompanion() {
        teachingPip?.close()
        teachingPip = nil
        companionPanel.isHidden = false
        positionBubble()
    }

    /// Every 1.5 s while a reply about Excel is open: the card shows what is really selected and ticks steps.
    func watchSelection() {
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
}
