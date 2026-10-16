import AppKit
import CoachCore

/// Pip's ··· menu, Settings, the learning and profile window, and permission and diagnostics actions for
/// CompanionController. Mirrors MainWindow.Menu.cs.
extension CompanionController {
    /// Pip's ··· menu, built each time it opens so it shows what is true now (which AI has a key, whether a
    /// highlight or a moved input bar can be put back). Preferences, permissions and keys live in Settings.
    func buildMenu() {
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(MenuAction.item("New chat") { [unowned self] _ in newChat() })
        menu.addItem(MenuAction.item("My learning & profile…") { [unowned self] _ in showProfile() })
        menu.addItem(.separator())
        let current = LocalSettings.provider()
        let providers = NSMenu()
        for provider in Provider.allCases {
            let ready = !LocalSettings.read(provider.key).isEmpty
            let item = MenuAction.item(provider.name, checked: provider == current) { [unowned self] _ in
                LocalSettings.setProvider(provider)
                if !ready { showSettings() }
            }
            item.subtitle = ready ? "Key added" : "No key yet · add it in Settings"
            providers.addItem(item)
        }
        providers.addItem(.separator())
        providers.addItem(MenuAction.item("Add or change keys…") { [unowned self] _ in showSettings() })
        let providerItem = NSMenuItem(title: "AI: \(current.name)", action: nil, keyEquivalent: "")
        providerItem.submenu = providers
        menu.addItem(providerItem)
        menu.addItem(MenuAction.item("Share my screen with Pip", checked: screenSharingEnabled) { [unowned self] _ in
            screenSharingEnabled.toggle()
            if !screenSharingEnabled { clearHighlight(); selectionEnabled = false; bubble.updateSelection(nil, line: "") }
        })
        let sizes = NSMenu()
        for (title, size) in Self.pipSizes {
            sizes.addItem(MenuAction.item(title, checked: size == pipSize) { [unowned self] _ in
                if userPositioned { moveWindow(dy: -(size.height - pipSize.height) / 2) }
                pipSize = size
                layoutCompanion()
            })
        }
        let sizeMenu = NSMenuItem(title: "Pip size", action: nil, keyEquivalent: "")
        sizeMenu.submenu = sizes
        menu.addItem(sizeMenu)
        menu.addItem(MenuAction.item("Move Pip to the other side") { [unowned self] _ in leftAnchor.toggle(); userPositioned = false; layoutCompanion() })
        if guide != nil { menu.addItem(MenuAction.item("Clear the highlight") { [unowned self] _ in clearHighlight() }) }
        if inputMoved { menu.addItem(MenuAction.item("Put the input bar back") { [unowned self] _ in inputMoved = false; layoutInputBar(); positionBubble() }) }
        menu.addItem(MenuAction.item("Hide the input bar") { [unowned self] _ in minimiseConversation() })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Settings…") { [unowned self] _ in showSettings() })
        menu.addItem(MenuAction.item("Quit F2L") { _ in NSApp.terminate(nil) })
    }

    static let pipSizes = [("Small", CGSize(width: 112, height: 128)), ("Medium", CGSize(width: 144, height: 164)),
                                   ("Large", CGSize(width: 180, height: 205))]

    func popUpMenu(from button: NSView) {
        buildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(hooks: .init(
                reducedMotion: { [unowned self] in reducedMotion },
                setReducedMotion: { [unowned self] on in setReducedMotion(on) },
                followTargets: { [unowned self] in followTargets },
                setFollowTargets: { [unowned self] on in
                    followTargets = on
                    if on, let target = lastTargetBounds { updateTeachingCompanion(target) } else { stopTeachingCompanion() }
                },
                resetPermissions: { [unowned self] in fixPermissions() },
                saveDiagnostics: { [unowned self] in saveDiagnostics() }))
        }
        NSApp.activate()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func setReducedMotion(_ on: Bool) {
        reducedMotion = on
        bubble.reducedMotion = on
        pipHost.pip.setReducedMotion(on)
        teachingPip?.reducedMotion = on
        teachingPip?.pip.setReducedMotion(on)
    }

    func showProfile() {
        if let personalizeWindow, personalizeWindow.isVisible { personalizeWindow.makeKeyAndOrderFront(nil); return }
        minimiseConversation()
        let setup = PersonalizeWindow(store: profileStore, coach: coach)
        personalizeWindow = setup
        setup.onDone = { [weak self] in
            guard let self else { return }
            profileDocument = testing ? ProfileDocument() : profileStore.load()
            openConversation(); greet()
        }
        setup.onChange = { [weak self] in
            guard let self, !testing else { return }
            profileDocument = profileStore.load()
        }
        setup.onSettings = { [weak self] in self?.showSettings() }
        NSApp.activate()
        setup.makeKeyAndOrderFront(nil)
    }

    /// macOS keeps asking (or keeps saying no) when its Screen Recording, Accessibility or Automation entry for F2L
    /// belongs to an older build. This clears F2L's own entries, then asks once, fresh, for the current app.
    func fixPermissions() {
        for service in ["ScreenCapture", "Accessibility", "AppleEvents"] {
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", service, Bundle.main.bundleIdentifier ?? "ai.f2l.companion"]
            try? reset.run()
            reset.waitUntilExit()
        }
        shownAccessibilityTip = false
        DesktopAccessibility.requestTrust()
        say("Permissions cleared. Turn F2L on under Accessibility, then quit and reopen F2L. I'll ask for Screen Recording and Excel the next time you ask a question.")
    }

    func saveDiagnostics() {
        let app = capture.target()
        Task {
            let message = await PointingDiagnostics.save(app: app, capture: capture, excel: selectionReader)
            say(message)
        }
    }
}
