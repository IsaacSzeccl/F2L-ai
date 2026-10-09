import AppKit
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
        if PipSprites.expressions.count != 16 || PipSprites.directions.count != 16 { failures.append("Pip sprites did not load (expected 16 + 16)") }
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
