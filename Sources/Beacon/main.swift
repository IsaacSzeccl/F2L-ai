import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = PermissionCenter()
    private let model = IslandModel()
    private var overlay: OverlayController?
    private var session: CoachSession?
    private var island: IslandController?
    private let pushToTalk = PushToTalk()
    private var onboarding: HostedWindow?
    private var settings: HostedWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_: Notification) {
        guard Bundle.main.bundleIdentifier != nil else {
            // macOS kills an unbundled process that touches the microphone. Use scripts/run.sh.
            Log.app.fault("Beacon must run as Beacon.app. Build it with scripts/build-app.sh.")
            print("Beacon must run as an app bundle: run ./scripts/run.sh")
            NSApp.terminate(nil)
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
        menu.addItem(MenuAction.item("Settings…") { [unowned self] in settings?.show() })
        menu.addItem(MenuAction.item("Privacy & permissions…") { [unowned self] in onboarding?.show() })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Quit Beacon") { NSApp.terminate(nil) })
        item.menu = menu
        statusItem = item
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
