import AppKit
import CoachCore

/// `F2L --rehearse` runs a lesson's real pointing on the app as it is on screen, without the companion, and saves a
/// picture of each step with the circle Pip would draw (solid when confirmed, dashed when only the AI's guess) and
/// a line in report.txt. Nothing is clicked. For checking a demo step by step:
///
///   open -n -g build/F2L.app --args --rehearse ask <question.txt> <dir> [app name]   the question; checks step 1
///   open -n -g build/F2L.app --args --rehearse step <n> <dir> [app name]             step n (from 1), as it is now
///
/// The app defaults to Google Chrome. `ask` saves the lesson in <dir>/lesson.json for the later `step` runs.
@MainActor
enum Rehearse {
    struct Lesson: Codable { var goal: String; var reply: String; var steps: [String]; var labels: [String?] }

    static func run(_ arguments: [String]) async {
        guard arguments.count >= 3 else { return }
        let mode = arguments[0], directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let appName = arguments.count > 3 ? arguments[3] : "Google Chrome"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let coach = CoachClient()
        guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
            report("\(appName) isn't open.", in: directory); return
        }
        let app = ForegroundApp(pid: running.processIdentifier, name: appName, bundleID: running.bundleIdentifier)
        let capture = ScreenCaptureService()
        guard let shot = try? await capture.capture(app) else { report("Couldn't picture \(appName).", in: directory); return }
        let names = await screenNames(shot)
        let controlDump = await Task.detached { [pid = app.pid, frame = shot.frame] in
            DesktopAccessibility.controls(pid: pid, in: frame).map { "\($0.name)  @ \(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
        }.value
        try? controlDump.joined(separator: "\n").write(to: directory.appendingPathComponent("controls-\(mode)-\(arguments[1].count < 4 ? arguments[1] : "1").txt"),
                                                      atomically: true, encoding: .utf8)
        let lessonFile = directory.appendingPathComponent("lesson.json")
        let number: Int
        var target: ScreenTarget?
        var lesson: Lesson
        var note = ""
        if mode == "ask" {
            let question = (try? String(contentsOfFile: arguments[1], encoding: .utf8)) ?? ""
            let profile = ProfileStore().load().profile
            let title = ScreenCaptureService.windowTitle(of: app.pid)
            do {
                let answer = try await coach.answer(question: CoachClient.compose(question: question, platform: "macOS", excel: nil,
                    profile: profile, app: appName, windowTitle: title, screenNames: names, library: .shared, recipes: .shared),
                    history: [], jpeg: shot.jpeg)
                let places = answer.placesForSteps
                lesson = Lesson(goal: question, reply: answer.reply, steps: answer.steps, labels: places.map { $0?.label })
                try? JSONEncoder().encode(lesson).write(to: lessonFile)
                target = answer.steps.isEmpty ? answer.placeForReply : places.first ?? nil
                number = 0
                report("Reply: \(answer.reply)\n" + answer.steps.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
                       in: directory)
            } catch {
                report("Question failed: \((error as? CoachRequestError)?.message ?? "\(error)")", in: directory); return
            }
        } else {
            guard let data = try? Data(contentsOf: lessonFile), let saved = try? JSONDecoder().decode(Lesson.self, from: data),
                  let n = Int(arguments[1]), saved.steps.indices.contains(n - 1) else {
                report("No lesson saved in \(directory.path), or no such step.", in: directory); return
            }
            lesson = saved; number = n - 1
            // As the companion does for every step after the first: a fresh picture, and the AI says where it happens.
            if let answer = await coach.guideStep(goal: lesson.goal, steps: lesson.steps, number: number, platform: "macOS",
                                                  app: appName, screenNames: names, jpeg: shot.jpeg) {
                target = answer.target ?? (answer.note.isEmpty ? NamedPlace.target(in: lesson.steps[number]) : nil).map {
                    ScreenTarget(left: 0, top: 0, right: 0, bottom: 0, label: $0.label, cell: $0.cell)
                }
                note = answer.note
            } else {
                target = NamedPlace.target(in: lesson.steps[number]).map { ScreenTarget(left: 0, top: 0, right: 0, bottom: 0, label: $0.label, cell: $0.cell) }
                note = "(step request failed; found by name only)"
            }
        }
        let step = lesson.steps.indices.contains(number) ? lesson.steps[number] : lesson.reply
        guard let target else {
            report("Step \(number + 1): \(step)\n  no place given\(note.isEmpty ? "" : "\n  note: \(note)")", in: directory)
            return
        }
        let estimate = target.hasBox ? CompanionPlacement.fromScreenshot(window: shot.frame, target: target) : nil
        let lines = await Task.detached(operation: { [jpeg = shot.jpeg, frame = shot.frame] in ScreenReading.lines(jpeg: jpeg, frame: frame) }).value
        var log: [String: Any] = [:]
        let recipes = CoachClient.reference(question: lesson.goal, app: appName, library: .shared, recipes: .shared).recipes
        // A cell is found from Excel's column letters and row numbers on screen, as the companion does on the Mac.
        try? lines.map { $0.map { "\($0.text)@\(Int($0.frame.minX)),\(Int($0.frame.minY))" }.joined(separator: "  ") }.joined(separator: "\n")
            .write(to: directory.appendingPathComponent("words-step-\(number + 1).txt"), atomically: true, encoding: .utf8)
        let cellName = target.cell ?? (app.isExcel ? CellReference.parse(target.label)?.address : nil)
        var gridPlace: CGRect?
        if let cell = cellName, app.isExcel, ScreenText.excelCell(cell, words: lines.flatMap { $0 }) == nil,
           let grid = await Task.detached(operation: { [pid = app.pid, frame = shot.frame] in DesktopAccessibility.largest(role: "AXLayoutArea", pid: pid, in: frame) }).value {
            gridPlace = ExcelGridReader.place(cell, jpeg: shot.jpeg, window: shot.frame, grid: grid, words: lines.flatMap { $0 })
            report("  (grid area \(grid), window \(shot.frame), found \(String(describing: gridPlace)))", in: directory)
        } else if cellName != nil {
            report("  (no worksheet area: excel \(app.isExcel), bundle \(app.bundleID ?? "-"))", in: directory)
        }
        if let cell = cellName, let place = ScreenText.excelCell(cell, words: lines.flatMap { $0 }) ?? gridPlace {
            let picture = directory.appendingPathComponent(String(format: "step-%02d.png", number + 1))
            draw(shot, place: place, confirmed: true, estimate: estimate, to: picture)
            report("Step \(number + 1): \(step)\n  cell: \(cell)   found: \(gridPlace == nil ? "screen-headings" : "excel-gridlines")   at x \(Int(place.minX)) y \(Int(place.minY))"
                   + (note.isEmpty ? "" : "\n  note: \(note)") + "\n  picture: \(picture.lastPathComponent)", in: directory)
            return
        }
        let found = await PlaceFinder(coach: coach).find(label: target.label, estimate: estimate, app: appName, bundleID: app.bundleID, pid: app.pid,
                                                          window: shot.frame, lines: lines, picture: shot.jpeg, step: step,
                                                          recipes: recipes, trusted: DesktopAccessibility.isTrusted, log: &log)
        let place = found.place ?? estimate
        let source = found.place == nil && estimate != nil ? "model-estimate" : found.source
        var line = "Step \(number + 1): \(step)\n  label: \(target.label)   found: \(source)"
        if let matched = log["matched"] as? String, !matched.isEmpty { line += "   matched: \(matched)" }
        if let place { line += "   at x \(Int(place.minX)) y \(Int(place.minY)) w \(Int(place.width)) h \(Int(place.height))" }
        if let done = found.alreadyDone { line += "\n  already done: shows \(done)" }
        if let hint = found.recipeHint { line += "\n  hint: \(hint)" }
        if !note.isEmpty { line += "\n  note: \(note)" }
        let picture = directory.appendingPathComponent(String(format: "step-%02d.png", number + 1))
        draw(shot, place: place, confirmed: !source.hasPrefix("model") && found.place != nil, estimate: estimate, to: picture)
        report(line + "\n  picture: \(picture.lastPathComponent)", in: directory)
    }

    /// The same names the companion sends with a question: the window's controls, then the words read on screen.
    static func screenNames(_ shot: CapturedScreen) async -> [String] {
        let jpeg = shot.jpeg, frame = shot.frame, pid = shot.app.pid, trusted = DesktopAccessibility.isTrusted
        async let controls = Task.detached { trusted ? DesktopAccessibility.controls(pid: pid, in: frame, limit: 2500, budget: 0.6).map(\.name) : [] }.value
        async let read = Task.detached { ScreenReading.lines(jpeg: jpeg, frame: frame).map { $0.map(\.text).joined(separator: " ") } }.value
        return await controls + read
    }

    static func report(_ line: String, in directory: URL) {
        let file = directory.appendingPathComponent("report.txt")
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        text += line + "\n\n"
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// The window picture with Pip's circle on it: green when confirmed on screen, orange dashed for the AI's guess.
    static func draw(_ shot: CapturedScreen, place: CGRect?, confirmed: Bool, estimate: CGRect?, to url: URL) {
        guard let source = CGImageSourceCreateWithData(shot.jpeg as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func pixels(_ r: CGRect) -> CGRect {
            let sx = w / shot.frame.width, sy = h / shot.frame.height
            // Screen rects are top-left; the bitmap context is bottom-left.
            return CGRect(x: (r.minX - shot.frame.minX) * sx, y: h - (r.maxY - shot.frame.minY) * sy, width: r.width * sx, height: r.height * sy)
        }
        if let estimate {
            context.setStrokeColor(CGColor(red: 0.3, green: 0.6, blue: 1, alpha: 0.9)); context.setLineWidth(3); context.setLineDash(phase: 0, lengths: [6, 6])
            context.stroke(pixels(estimate))
        }
        if let place {
            context.setLineDash(phase: 0, lengths: confirmed ? [] : [10, 8])
            context.setStrokeColor(confirmed ? CGColor(red: 0.1, green: 0.85, blue: 0.3, alpha: 1) : CGColor(red: 1, green: 0.55, blue: 0, alpha: 1))
            context.setLineWidth(5)
            context.strokeEllipse(in: pixels(TargetSnap.circle(around: place)))
        }
        guard let out = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, out, nil)
        CGImageDestinationFinalize(destination)
    }
}
