import AppKit
import CoachCore
import Speech
import SwiftUI

/// Hosts a SwiftUI view in an ordinary titled window (onboarding, settings). These windows do take focus.
@MainActor
final class HostedWindow {
    private var window: NSWindow?
    private let title: String
    private let size: CGSize
    private let makeView: () -> AnyView

    init(title: String, size: CGSize, makeView: @escaping () -> AnyView) {
        self.title = title
        self.size = size
        self.makeView = makeView
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: makeView())
            window.center()
            self.window = window
        }
        // An accessory app can't always win activation (cooperative activation), so also force the
        // window to the front; otherwise first-run onboarding could open hidden behind other apps.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }
}

// MARK: - Onboarding / privacy

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionCenter
    let onStart: () -> Void

    @State private var closedPrivateThings = Preferences.onboardingAccepted

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Orb(phase: .idle, paused: false).frame(width: 36, height: 36)
                VStack(alignment: .leading) {
                    Text("Welcome to Beacon").font(.title2.bold())
                    Text("A voice coach that points to where you click.").foregroundStyle(.secondary)
                }
            }

            GroupBox("What Beacon sees, and where it goes") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(PrivacyCopy.lines(onDeviceSpeech: SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition ?? false), id: \.self) { line in
                        Label(line, systemImage: "checkmark.shield").font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Permissions") {
                VStack(spacing: 8) {
                    ForEach(Permission.allCases) { permission in
                        HStack {
                            Image(systemName: permissions.granted[permission] == true ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(permissions.granted[permission] == true ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(permission.title).bold()
                                Text(permission.why).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if permissions.granted[permission] != true {
                                Button("Allow") { permissions.request(permission) }
                            }
                        }
                    }
                    if permissions.screenRecordingNeedsRelaunch || (permissions.granted[.screenRecording] != true) {
                        HStack {
                            Text("After allowing Screen Recording, macOS needs Beacon to restart.").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restart Beacon") { PermissionCenter.relaunch() }
                        }
                    }
                }
                .padding(6)
            }

            Toggle(isOn: $closedPrivateThings) {
                Text("I've closed anything private (banking, email, personal messages) before starting.")
            }

            HStack {
                Spacer()
                Button("Start") {
                    Preferences.onboardingAccepted = true
                    onStart()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!permissions.allGranted || !closedPrivateThings)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }
}

// MARK: - Settings

struct SettingsView: View {
    let onTestVoice: () -> Void

    @State private var provider = Preferences.provider
    @State private var model = Preferences.model
    @State private var summaryModel = Preferences.summaryModel
    @State private var summaryLoop = Preferences.summaryLoopEnabled
    @State private var voiceID = Preferences.voiceID
    @State private var ttsModel = Preferences.ttsModel
    @State private var keys: [SecretKey: String] = [:]
    @State private var saved = false

    var body: some View {
        Form {
            Section("AI model") {
                Picker("Provider", selection: $provider) {
                    ForEach(LLMProvider.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: provider) { _, newValue in
                    Preferences.provider = newValue
                    model = Preferences.model
                    summaryModel = Preferences.summaryModel
                }
                TextField("Coach model", text: $model, prompt: Text(provider.defaultModel))
                TextField("Screen summary model", text: $summaryModel, prompt: Text(provider.defaultSummaryModel))
                Toggle("Background screen summary", isOn: $summaryLoop)
            }
            Section("Voice (ElevenLabs)") {
                TextField("Voice ID", text: $voiceID)
                TextField("Model", text: $ttsModel)
                Button("Test voice", action: onTestVoice)
            }
            Section("API keys (stored in your Keychain)") {
                ForEach(SecretKey.allCases, id: \.self) { key in
                    HStack {
                        SecureField(key.displayName, text: binding(for: key), prompt: Text(Secrets.has(key) ? "Saved. Type to replace." : "Not set"))
                        Image(systemName: Secrets.has(key) ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(Secrets.has(key) ? .green : .secondary)
                    }
                }
            }
            HStack {
                if saved { Text("Saved").foregroundStyle(.green) }
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }

    private func binding(for key: SecretKey) -> Binding<String> {
        Binding(get: { keys[key] ?? "" }, set: { keys[key] = $0; saved = false })
    }

    private func save() {
        Preferences.provider = provider
        Preferences.model = model
        Preferences.summaryModel = summaryModel
        Preferences.summaryLoopEnabled = summaryLoop
        Preferences.voiceID = voiceID
        Preferences.ttsModel = ttsModel
        for (key, value) in keys where !value.trimmingCharacters(in: .whitespaces).isEmpty {
            Secrets.write(value, for: key)
        }
        keys.removeAll()
        saved = true
    }
}
