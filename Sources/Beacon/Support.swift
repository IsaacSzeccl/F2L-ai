import AppKit
import CoachCore
import Foundation
import os
import Security

enum Log {
    static let subsystem = "app.beacon.coach"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let voice = Logger(subsystem: subsystem, category: "voice")
    static let llm = Logger(subsystem: subsystem, category: "llm")
    static let screen = Logger(subsystem: subsystem, category: "screen")
    /// `log stream --predicate 'subsystem == "app.beacon.coach" AND category == "latency"'`
    static let latency = Logger(subsystem: subsystem, category: "latency")
}

// MARK: - Secrets

enum SecretKey: String, CaseIterable {
    case zai = "ZAI_API_KEY"
    case anthropic = "ANTHROPIC_API_KEY"
    case elevenLabs = "ELEVENLABS_API_KEY"

    var displayName: String {
        switch self {
        case .zai: "z.ai API key"
        case .anthropic: "Anthropic API key (optional fallback)"
        case .elevenLabs: "ElevenLabs API key"
        }
    }
}

/// API keys live in the login Keychain, never in the repo or the app bundle.
/// An environment variable of the same name overrides the Keychain (handy for development).
@MainActor
enum Secrets {
    private static let service = "app.beacon.coach"
    /// Keychain reads can block on an access prompt, so each key is read once and kept in memory.
    private static var cache: [SecretKey: String] = [:]
    /// Keys from a `.env` file next to the project (development convenience), read once at first use.
    /// The app lives in <project>/build/Beacon.app, so the search starts above the bundle.
    private static let dotEnv: [String: String] = {
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
        var values = DotEnv.load(from: bundleParent)
        if values.isEmpty { values = DotEnv.load(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) }
        return values
    }()

    static func read(_ key: SecretKey) -> String {
        if let cached = cache[key] { return cached }
        let value = readUncached(key)
        if !value.isEmpty { cache[key] = value } // a failed or denied read is retried next time
        return value
    }

    private static func readUncached(_ key: SecretKey) -> String {
        if let env = ProcessInfo.processInfo.environment[key.rawValue], !env.isEmpty { return env }
        if let fromFile = dotEnv[key.rawValue], !fromFile.isEmpty { return fromFile }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ value: String, for key: SecretKey) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        cache[key] = nil
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { Log.app.error("Keychain write failed: \(status)") }
    }

    static func has(_ key: SecretKey) -> Bool { !read(key).isEmpty }
}

// MARK: - Local switches

/// Reads a setting from the real environment, then from the project's `.env` file. The file is read fresh
/// every time, so editing it takes effect without restarting Beacon.
enum LocalEnv {
    static func value(_ key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty { return env }
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
        var values = DotEnv.load(from: bundleParent)
        if values.isEmpty { values = DotEnv.load(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) }
        return values[key]
    }
}

enum BugReports {
    /// `BEACON_BUG_REPORTS=off` (environment or `.env`) turns the whole feature off: the buttons disappear,
    /// nothing is captured, and nothing is written.
    static var isEnabled: Bool { !DotEnv.isOff(LocalEnv.value("BEACON_BUG_REPORTS")) }
}

// MARK: - Settings

/// Non-secret preferences, stored in UserDefaults.
@MainActor
enum Preferences {
    private static let defaults = UserDefaults.standard

    static var provider: LLMProvider {
        get { LLMProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .zai }
        set { defaults.set(newValue.rawValue, forKey: "provider") }
    }

    static var model: String {
        get { nonEmpty(defaults.string(forKey: "model.\(provider.rawValue)")) ?? provider.defaultModel }
        set { defaults.set(newValue, forKey: "model.\(provider.rawValue)") }
    }

    static var summaryModel: String {
        get { nonEmpty(defaults.string(forKey: "summaryModel.\(provider.rawValue)")) ?? provider.defaultSummaryModel }
        set { defaults.set(newValue, forKey: "summaryModel.\(provider.rawValue)") }
    }

    static var summaryLoopEnabled: Bool {
        get { defaults.object(forKey: "summaryLoopEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "summaryLoopEnabled") }
    }

    /// ElevenLabs premade voice "George"; replace with any voice id from your ElevenLabs library.
    static var voiceID: String {
        get { nonEmpty(defaults.string(forKey: "voiceID")) ?? "JBFqnCBsd6RMkjVDRZzb" }
        set { defaults.set(newValue, forKey: "voiceID") }
    }

    static var ttsModel: String {
        get { nonEmpty(defaults.string(forKey: "ttsModel")) ?? "eleven_flash_v2_5" }
        set { defaults.set(newValue, forKey: "ttsModel") }
    }

    /// Which English (or Chinese) model Apple's recognizer uses. en-HK often suits Hong Kong accents better.
    static var speechLocale: String {
        get { nonEmpty(defaults.string(forKey: "speechLocale")) ?? "en-US" }
        set { defaults.set(newValue, forKey: "speechLocale") }
    }

    /// True keeps your voice on this Mac (more private). False lets Apple's servers recognise it (usually more accurate).
    static var speechOnDeviceOnly: Bool {
        get { defaults.object(forKey: "speechOnDeviceOnly") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "speechOnDeviceOnly") }
    }

    /// CoreAudio UID of the chosen microphone; nil follows the system default.
    static var inputDeviceUID: String? {
        get { nonEmpty(defaults.string(forKey: "inputDeviceUID")) }
        set { defaults.set(newValue, forKey: "inputDeviceUID") }
    }

    /// Shows developer tools (spike snapshots) in the menu: `defaults write app.beacon.coach developerMode -bool true`.
    static var developerMode: Bool { defaults.bool(forKey: "developerMode") }

    static var onboardingAccepted: Bool {
        get { defaults.bool(forKey: "onboardingAccepted") }
        set { defaults.set(newValue, forKey: "onboardingAccepted") }
    }

    static func llmSettings(summary: Bool = false) -> LLMSettings {
        let key: SecretKey = provider == .zai ? .zai : .anthropic
        return LLMSettings(
            provider: provider,
            model: summary ? summaryModel : model,
            apiKey: Secrets.read(key),
            maxTokens: summary ? 80 : 400
        )
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }
}

// MARK: - Privacy copy

/// Everything the start screen promises about data, in one place. Keep it true: update it if a vendor
/// or what it receives changes. See SETUP.md for the retention facts you must confirm before Oct 18.
@MainActor
enum PrivacyCopy {
    static var aiVendor: String {
        Preferences.provider == .zai ? "z.ai (Zhipu AI, based in China)" : "Anthropic (based in the US)"
    }

    /// `onDeviceSpeech`: whether Apple's on-device recognizer is available on this Mac.
    static func lines(onDeviceSpeech: Bool) -> [String] {
        var lines = [
            "Beacon looks only at the window in front of you, so it can point at the right thing.",
            "To answer you, it sends \(aiVendor) a picture of that window, a list of its buttons and boxes (including any text typed in them), and your words as text. Their data policy applies to what they receive.",
        ]
        if Preferences.summaryLoopEnabled {
            lines.append("While Beacon is on, it also sends a picture of each new window you switch to, so it's ready to help. You can turn this off in Settings.")
        }
        lines.append(onDeviceSpeech
            ? "Your voice is turned into text on this Mac by Apple. It is not sent anywhere."
            : "Your voice is sent to Apple's speech service to be turned into text. You can change this in Settings.")
        lines += [
            "Only the coach's replies are sent to ElevenLabs, to give it a voice. ElevenLabs never sees your screen.",
            "Beacon never saves pictures of your screen on its own. The only exception is the Report a bug button: it saves the last screenshot, your note and the logs into a folder on this Mac, only when you press it.",
            "No pictures are taken while a password box is selected, and you can pause Beacon at any time from the bar at the top of your screen.",
        ]
        return lines
    }
}

extension NSScreen {
    /// AppKit's global coordinates are anchored to the first screen (the one with the menu bar).
    static var primaryHeight: CGFloat { screens.first?.frame.height ?? 0 }

    /// This screen's frame in global top-left-origin coordinates (Accessibility / CoreGraphics space).
    var topLeftFrame: CGRect {
        CGRect(x: frame.minX, y: NSScreen.primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
