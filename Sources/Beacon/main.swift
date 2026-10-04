import AppKit
import CoachCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let permissions = PermissionCenter()
    private let model = IslandModel()
    private var overlay: OverlayController?
    private var session: CoachSession?
    private var island: IslandController?
    private let pushToTalk = PushToTalk()
    private var onboarding: HostedWindow?
    private var settings: HostedWindow?
    private var statusItem: NSStatusItem?
    private let bugReporter = BugReportController()
    private var bugMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_: Notification) {
        guard Bundle.main.bundleIdentifier != nil else {
            // macOS kills an unbundled process that touches the microphone. Use scripts/run.sh.
            Log.app.fault("Beacon must run as Beacon.app. Build it with scripts/build-app.sh.")
            print("Beacon must run as an app bundle: run ./scripts/run.sh")
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--write-test-bug-report") {
            writeTestBugReport()
            return
        }
        onboarding = HostedWindow(title: "Beacon", size: CGSize(width: 560, height: 640)) { [unowned self] in
            AnyView(OnboardingView(permissions: permissions) { [unowned self] in
                onboarding?.close()
                startCoach()
            })
        }
        settings = HostedWindow(title: "Beacon Settings", size: CGSize(width: 540, height: 720)) { [unowned self] in
            AnyView(SettingsView { [unowned self] in session?.testVoice() })
        }

        permissions.refresh()
        if permissions.allGranted && Preferences.onboardingAccepted {
            startCoach()
        } else {
            onboarding?.show()
        }
    }

    private func startCoach() {
        guard session == nil else { return }
        let overlay = OverlayController()
        let session = CoachSession(model: model, overlay: overlay)
        self.overlay = overlay
        self.session = session

        island = IslandController(model: model, actions: IslandActions(
            pressTalk: { session.beginListening() },
            releaseTalk: { session.endListening(cancelled: false) },
            togglePause: { session.togglePause() },
            clearPointer: { session.clearPointer() },
            submitText: { session.submitText($0) },
            newConversation: { session.resetConversation() },
            reportBug: { [unowned self] in reportBug() },
            openSettings: { [unowned self] in settings?.show() },
            openOnboarding: { [unowned self] in onboarding?.show() },
            saveSnapshot: { [unowned self] in saveSnapshot() },
            quit: { NSApp.terminate(nil) }
        ))

        installStatusItem()

        pushToTalk.onPress = { session.beginListening() }
        pushToTalk.onRelease = { cancelled in session.endListening(cancelled: cancelled) }
        pushToTalk.start()

        if !Secrets.has(Preferences.provider == .zai ? .zai : .anthropic) {
            model.hasError = true
            model.status = "Add your AI API key in Settings (hover here → ⋯)"
            settings?.show()
        }
    }

    /// A menu-bar icon as a second way to reach Settings, Pause and Quit, independent of the island.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "light.beacon.max", accessibilityDescription: "Beacon") {
            item.button?.image = image
        } else {
            item.button?.title = "◉"
        }
        let menu = NSMenu()
        menu.addItem(MenuAction.item("Type a question…") { [unowned self] in island?.focusInput() })
        menu.addItem(MenuAction.item("Pause / Resume") { [unowned self] in session?.togglePause() })
        menu.addItem(MenuAction.item("Start over") { [unowned self] in session?.resetConversation() })
        menu.addItem(.separator())
        let bugItem = MenuAction.item("Report a bug…") { [unowned self] in reportBug() }
        bugMenuItem = bugItem
        menu.addItem(bugItem)
        menu.addItem(MenuAction.item("Settings…") { [unowned self] in settings?.show() })
        menu.addItem(MenuAction.item("Privacy & permissions…") { [unowned self] in onboarding?.show() })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Quit Beacon") { NSApp.terminate(nil) })
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Re-checks BEACON_BUG_REPORTS each time the menu opens, so the item appears and disappears live.
    func menuNeedsUpdate(_ menu: NSMenu) {
        bugMenuItem?.isHidden = !BugReports.isEnabled
    }

    /// Headless check of the bug-report writer: `Beacon.app/Contents/MacOS/Beacon --write-test-bug-report`.
    private func writeTestBugReport() {
        Log.app.notice("Self-test: writing a sample bug report")
        var turn = TurnDebug(trigger: "Learner said: \"where do I type?\"", provider: "zai", model: "glm-4.6v", appName: "Google Chrome",
                             windowTitle: "ChatGPT", windowFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))
        turn.elements = [ScreenElement(id: "e1", role: "AXTextArea", label: "Ask anything", frame: CGRect(x: 400, y: 600, width: 600, height: 50))]
        turn.promptContext = PromptBuilder.describe(ScreenContext(appName: "Google Chrome", windowTitle: "ChatGPT", windowFrame: turn.windowFrame, elements: turn.elements))
        turn.spoken = "Click the box that says Ask anything."
        turn.toolCalls = ["`point_at` {\"element_id\":\"e1\"} → drew a circle (you circled \"Ask anything\")"]
        turn.screenshot = ImageAttachment(jpegBase64: "QUJD", pixelWidth: 1, pixelHeight: 1)
        let snapshot = BugSnapshot(phase: "idle", status: "Hold right ⌥ to reply", heard: "where do I type?", reply: turn.spoken,
                                   history: [ChatMessage(role: .user, text: "hi"), ChatMessage(role: .assistant, text: "Hello!")],
                                   turn: turn, latency: "self-test", permissions: ["Microphone": true, "Screen Recording": false])
        do {
            let folder = try BugReportWriter.write(snapshot, note: "Self test: the circle was in the wrong place", includeScreenshot: true)
            print("WROTE \(folder.path)")
        } catch {
            print("FAILED \(error)")
        }
        NSApp.terminate(nil)
    }

    /// Captures the state right now (before the learner writes their note), then opens the report window.
    private func reportBug() {
        guard BugReports.isEnabled else {
            model.status = "Bug reports are turned off (BEACON_BUG_REPORTS=off)"
            return
        }
        guard let session else { return }
        permissions.refresh()
        let granted = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0.title, permissions.granted[$0] == true) })
        bugReporter.present(session.bugSnapshot(permissions: granted))
    }

    private func saveSnapshot() {
        guard let session else { return }
        model.status = "Saving snapshot in 3s. Click into the window to capture."
        Task {
            try? await Task.sleep(for: .seconds(3))
            if let url = await session.saveSpikeSnapshot() {
                model.status = "Saved \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                model.status = "Could not save snapshot"
            }
        }
    }
}

/// Closure-backed menu item target.
@MainActor
final class MenuAction: NSObject {
    private let handler: () -> Void
    private static var retained: [MenuAction] = []

    private init(_ handler: @escaping () -> Void) { self.handler = handler }

    static func item(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        retained.append(action)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = action
        return item
    }

    @objc private func run() { handler() }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
