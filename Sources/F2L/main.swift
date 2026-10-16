import AppKit
import AVFoundation
import CoachCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var companion: CompanionController?
    private var termination: DispatchSourceSignal?

    func applicationDidFinishLaunching(_: Notification) {
        Fonts.register()
        installEditMenu()
        // `kill`/`pkill` (scripts/run.sh, the launcher) quit like ⌘Q, so the conversation and draft are saved.
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { NSApp.terminate(nil) }
        termination.resume()
        self.termination = termination
        if let index = CommandLine.arguments.firstIndex(of: "--export-emotes") {
            // Default: the shared artwork folder found from the binary (Windows/F2L.Windows/Assets/Pip/Emotes), not the shell's folder.
            let given = CommandLine.arguments.indices.contains(index + 1) ? URL(fileURLWithPath: CommandLine.arguments[index + 1]) : nil
            guard let target = given ?? Assets.url("Pip/Emotes") else { print("FAIL: Pip's artwork folder wasn't found"); exit(1) }
            let directory = target.path
            let failures = PipEmote.export(to: target)
            failures.forEach { print("FAIL: \($0)") }
            if failures.isEmpty { print("Exported \(PipEmote.allCases.count) emotes to \(directory)") }
            exit(failures.isEmpty ? 0 : 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--permissions") {
            // `open -n build/F2L.app --args --permissions <file>`: what macOS currently allows this exact build, without
            // asking for anything. Opened with `open`, F2L is checked as itself, not as the shell that started it.
            let path = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "/dev/stdout"
            let mic: [AVAuthorizationStatus: String] = [.authorized: "allowed", .denied: "denied", .restricted: "restricted", .notDetermined: "not asked"]
            let lines = ["accessibility: \(AXIsProcessTrusted() ? "allowed" : "not allowed")",
                         "screenRecording: \(CGPreflightScreenCaptureAccess() ? "allowed" : "not allowed")",
                         "microphone: \(mic[AVCaptureDevice.authorizationStatus(for: .audio)] ?? "unknown")",
                         "app: \(Bundle.main.bundlePath)"]
            try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--rehearse") {
            let rest = Array(CommandLine.arguments[(index + 1)...])
            Task { await Rehearse.run(rest); exit(0) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--ask"), CommandLine.arguments.indices.contains(index + 2) {
            // `open -n build/F2L.app --args --ask <question.txt> <reply.txt>`: the reply Pip's chosen AI gives this question,
            // as if asked in Gemini in Chrome, with the saved profile and recipes but no screenshot. For rehearsing a demo.
            let question = (try? String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8)) ?? ""
            let output = CommandLine.arguments[index + 2]
            Task {
                let composed = CoachClient.compose(question: question, platform: "macOS", excel: nil, profile: ProfileStore().load().profile,
                                                   app: "Google Chrome", windowTitle: "Google Gemini", library: .shared, recipes: .shared)
                let chosen = CoachClient.reference(question: question, profile: ProfileStore().load().profile, app: "Google Chrome",
                                                   windowTitle: "Google Gemini", library: .shared, recipes: .shared).recipes.map(\.id)
                let started = Date()
                var text = "recipes: \(chosen.joined(separator: ", "))\n"
                do {
                    let answer = try await CoachClient().answer(question: composed, history: [], jpeg: nil)
                    text += String(format: "seconds: %.1f\n\n", Date().timeIntervalSince(started)) + answer.text + "\n"
                } catch {
                    text += "error: \((error as? CoachRequestError)?.message ?? "\(error)")\n"
                }
                try? text.write(toFile: output, atomically: true, encoding: .utf8)
                exit(0)
            }
            return
        }
        // The checks draw real windows; keep them out of sight and click-through so a check never shows sample lessons
        // ("Click A1, then hold Shift and click A4") on the learner's screen. Drawing them into files still works.
        if CommandLine.arguments.contains("--soak") || CommandLine.arguments.contains("--render") {
            // Below the desktop picture: drawn as usual (so the numbers are real) but never seen or clicked.
            let hidden = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
            let hideAll = { NSApp.windows.filter { $0.level != hidden || !$0.ignoresMouseEvents }.forEach { $0.level = hidden; $0.ignoresMouseEvents = true } }
            NotificationCenter.default.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { hideAll() }
            }
            let hide = Timer(timeInterval: 0.05, repeats: true) { _ in MainActor.assumeIsolated { hideAll() } }
            RunLoop.main.add(hide, forMode: .common)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--soak") {
            let seconds = CommandLine.arguments.indices.contains(index + 1) ? Double(CommandLine.arguments[index + 1]) ?? 10 : 10
            SoakCheck.run(seconds: seconds)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render") {
            let directory = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "build/render"
            RenderCheck.run(into: URL(fileURLWithPath: directory))
            return
        }
        guard Assets.root != nil else {
            let alert = NSAlert()
            alert.messageText = "F2L can't find Pip's artwork"
            alert.informativeText = "Rebuild the app with scripts/build-app.sh, or run it from inside the F2L folder."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let companion = CompanionController()
        self.companion = companion
        companion.show(withIntro: true)
    }

    func applicationWillTerminate(_: Notification) { companion?.shutdown() }

    /// Reopening F2L (double-clicking the app or launcher again) brings the conversation up.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        companion?.show()
        companion?.openConversation()
        return false
    }

    /// Keeps standard editing shortcuts and ⌘Q working even though F2L shows no menu bar.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit F2L", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(appItem)
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}

/// `F2L --render <dir>` draws the real views with sample text into PNGs, then quits.
/// No network, microphone or screen capture is used. scripts/check.sh runs it.
@MainActor
enum RenderCheck {
    static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConversationStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("f2l-render-\(UUID().uuidString).json"))
        let companion = CompanionController(coach: CoachClient(apiKey: { "" }), store: store, testing: true)
        var failures: [String] = []
        if let error = ExcelSelectionReader.validateScript() { failures.append(error) }
        failures += ScreenReadingCheck.run()
        if PipSprites.expressions.count != 16 || PipSprites.directions.count != 16 || PipSprites.playful.count != 16 { failures.append("Pip sprites did not load (expected 16 + 16 + 16)") }
        for path in BrandArtwork.paths where BrandArtwork.image(path) == nil { failures.append("Brand artwork did not load: \(path)") }
        companion.show()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            write(companion.contentView, to: directory.appendingPathComponent("pip-resting.png"), failures: &failures)
            let intro = companion.makeIntro()
            for (seconds, name) in [(0.7, "intro-bounce.png"), (2.6, "intro-title.png"), (4.7, "intro-walk.png"), (6.05, "intro-arrival.png")] {
                intro.freeze(at: seconds)
                try? await Task.sleep(for: .milliseconds(150))
                if let view = intro.contentView { write(view, to: directory.appendingPathComponent(name), failures: &failures) }
            }
            if CommandLine.arguments.contains("--animate-intro") {
                await animateIntro(intro, to: directory.appendingPathComponent("intro-preview.gif"), failures: &failures)
            }
            intro.finish()
            let stillIntro = companion.makeIntro(reducedMotion: true)
            stillIntro.freeze(at: 0.8)
            try? await Task.sleep(for: .milliseconds(100))
            if let view = stillIntro.contentView { write(view, to: directory.appendingPathComponent("intro-reduced-motion.png"), failures: &failures) }
            stillIntro.finish()
            companion.sampleGreeting()
            companion.revealSample()
            try? await Task.sleep(for: .milliseconds(100))
            if let reply = companion.replyView { write(reply, to: directory.appendingPathComponent("pip-greeting.png"), failures: &failures) }
            companion.samplePersonalGreeting()
            companion.revealSample()
            try? await Task.sleep(for: .milliseconds(100))
            if let reply = companion.replyView { write(reply, to: directory.appendingPathComponent("pip-greeting-personal.png"), failures: &failures) }
            companion.seedSample(question: "How do I add up column B?", reply: "Click the empty cell under your numbers, then type =SUM(B2:B10) and press Return.")
            companion.revealSample()
            try? await Task.sleep(for: .milliseconds(100))
            if let reply = companion.replyView { write(reply, to: directory.appendingPathComponent("pip-reply.png"), failures: &failures) }
            companion.seedSample(question: "Select two ranges", reply: "Select both groups before inserting the chart.",
                                 steps: ["Click A1, then hold Shift and click A4.", "Hold Command and drag from D1 to D4.", "Open Insert and choose a chart."])
            companion.openConversation()
            try? await Task.sleep(for: .milliseconds(500))
            if let reply = companion.replyView { write(reply, to: directory.appendingPathComponent("pip-phrase-animating.png"), failures: &failures) }
            companion.revealSample()
            try? await Task.sleep(for: .milliseconds(100))
            if let reply = companion.replyView { write(reply, to: directory.appendingPathComponent("pip-lesson-start.png"), failures: &failures) }
            if let input = companion.inputView { write(input, to: directory.appendingPathComponent("pip-input.png"), failures: &failures) }
            if !companion.inputIsCentred { failures.append("input is not centred on the work area") }
            let profileURL = FileManager.default.temporaryDirectory.appendingPathComponent("f2l-profile-preview-\(UUID().uuidString).json")
            let welcome = PersonalizeWindow(store: ProfileStore(url: profileURL), coach: CoachClient(apiKey: { "" }))
            var learner = LearnerProfile()
            learner.name = "Alex"; learner.role = "Operations coordinator"; learner.goal = "Make weekly reporting easier and grow into a team lead role."
            learner.experience = "some"; learner.focus = "analyze"; learner.existingTools = ["excel", "notion"]
            learner.learning = ["Pivot tables", "Charts for reports"]
            for (step, name) in [(0, "setup-your-world.png"), (1, "setup-your-pace.png"), (2, "setup-your-path.png")] {
                welcome.preview(step: step, profile: learner)
                welcome.orderFrontRegardless()
                try? await Task.sleep(for: .milliseconds(150))
                if let view = welcome.contentView { write(view, to: directory.appendingPathComponent(name), failures: &failures) }
            }
            welcome.close()
            try? FileManager.default.removeItem(at: profileURL)
            // Settings only reads here: which providers have a key (never the key) and what macOS allows.
            let settings = SettingsWindow(hooks: .init(reducedMotion: { false }, setReducedMotion: { _ in }, followTargets: { false },
                                                       setFollowTargets: { _ in }, resetPermissions: {}, saveDiagnostics: {}))
            settings.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(150))
            if let view = settings.contentView { write(view, to: directory.appendingPathComponent("settings.png"), failures: &failures) }
            settings.close()
            companion.sampleStep()
            try? await Task.sleep(for: .milliseconds(100))
            if let reply = companion.replyView { write(reply, to: directory.appendingPathComponent("pip-step.png"), failures: &failures) }
            let work = ScreenSpace.workArea(at: CGPoint(x: 400, y: 400))
            companion.simulateTarget(CGRect(x: work.minX + 220, y: work.minY + 240, width: 120, height: 32))
            try? await Task.sleep(for: .milliseconds(600))
            if let circle = companion.guideView { write(circle, to: directory.appendingPathComponent("pip-circle.png"), failures: &failures) }
            if let teaching = companion.teachingWindow?.contentView {
                write(teaching, to: directory.appendingPathComponent("pip-teaching.png"), failures: &failures)
            } else {
                failures.append("teaching companion did not appear beside the target")
            }
            store.save(ConversationSession(), draft: "")
            try? FileManager.default.removeItem(at: store.url)
            if failures.isEmpty { print("Render check passed: \(directory.path)") } else { failures.forEach { print("FAIL: \($0)") } }
            fflush(stdout)
            exit(failures.isEmpty ? 0 : 1)
        }
    }

    /// Optional shareable preview of the native intro. Uses only our layers, never desktop pixels.
    private static func animateIntro(_ intro: IntroWindow, to url: URL, failures: inout [String]) async {
        let count = 77
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, count, nil),
              let view = intro.contentView else { failures.append("could not create intro preview"); return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<count {
            intro.freeze(at: Double(frame) * 0.08)
            try? await Task.sleep(for: .milliseconds(16))
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            let scale = min(1, 960 / view.bounds.width)
            guard let context = CGContext(data: nil, width: Int(view.bounds.width * scale), height: Int(view.bounds.height * scale), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { failures.append("could not draw intro frame"); return }
            context.setFillColor(Palette.hex(0x282632).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
            context.scaleBy(x: scale, y: scale)
            if view.layer?.isGeometryFlipped == true { context.translateBy(x: 0, y: view.bounds.height); context.scaleBy(x: 1, y: -1) }
            view.layer?.render(in: context)
            guard let image = context.makeImage() else { failures.append("could not encode intro frame"); return }
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]] as CFDictionary)
        }
        if !CGImageDestinationFinalize(destination) { failures.append("could not save intro preview") }
    }

    private static func write(_ view: NSView, to url: URL, failures: inout [String]) {
        view.layoutSubtreeIfNeeded()
        let scale = view.window?.backingScaleFactor ?? 2
        let size = view.bounds.size
        guard let layer = view.layer, size.width > 0,
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            failures.append("could not render \(url.lastPathComponent)")
            return
        }
        context.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            failures.append("could not encode \(url.lastPathComponent)")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
