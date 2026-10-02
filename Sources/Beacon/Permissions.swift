import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech

enum Permission: String, CaseIterable, Identifiable {
    case microphone, speechRecognition, screenRecording, accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .speechRecognition: "Speech Recognition"
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        }
    }

    var why: String {
        switch self {
        case .microphone: "So you can talk to the coach."
        case .speechRecognition: "Turns your voice into text, on this Mac."
        case .screenRecording: "Lets the coach see the window you're working in."
        case .accessibility: "Finds the exact button to circle, and notices when you've clicked it."
        }
    }

    var settingsURL: URL {
        let anchor = switch self {
        case .microphone: "Privacy_Microphone"
        case .speechRecognition: "Privacy_SpeechRecognition"
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var granted: [Permission: Bool] = [:]
    /// Screen Recording only takes effect after a relaunch once granted.
    @Published private(set) var screenRecordingNeedsRelaunch = false

    private var timer: Timer?

    init() { refresh() }

    var allGranted: Bool { Permission.allCases.allSatisfy { granted[$0] == true } }

    func refresh() {
        granted[.microphone] = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        granted[.speechRecognition] = SFSpeechRecognizer.authorizationStatus() == .authorized
        granted[.screenRecording] = CGPreflightScreenCaptureAccess()
        granted[.accessibility] = AXIsProcessTrusted()
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func request(_ permission: Permission) {
        switch permission {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in self.refresh() } }
        case .speechRecognition:
            SFSpeechRecognizer.requestAuthorization { _ in Task { @MainActor in self.refresh() } }
        case .screenRecording:
            // Shows the system prompt the first time; afterwards the user must toggle it in Settings.
            if !CGRequestScreenCaptureAccess() {
                screenRecordingNeedsRelaunch = true
                NSWorkspace.shared.open(permission.settingsURL)
            }
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                NSWorkspace.shared.open(permission.settingsURL)
            }
        }
        refresh()
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
