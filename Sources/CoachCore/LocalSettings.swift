import Foundation
import Security

/// Provider keys and choices, looked up the same way on Mac and Windows (Windows/F2L.Windows/CredentialStore.cs):
/// 1. environment variable (DEEPSEEK_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, ANTHROPIC_API_KEY, GLM_API_KEY,
///    ELEVENLABS_API_KEY; F2L_PROVIDER picks the provider)
/// 2. local.settings.json, the first that exists of:
///    - the per-user file: ~/Library/Application Support/F2L/local.settings.json (Windows: %APPDATA%\F2L\)
///    - the F2L folder the app was built from: <repo>/local.settings.json, or the older
///      <repo>/Windows/F2L.Windows/local.settings.json
///    - the file next to the app (a copied or unzipped F2L)
/// 3. the login keychain: a generic password with service "F2L" and the variable name as account
///    (Windows: Credential Manager "F2L/<variable>")
/// The file (never committed: see .gitignore and scripts/check-secrets.sh) looks like
/// {"Provider": "deepseek", "DeepSeekApiKey": "...", "ClaudeApiKey": "...", "ClaudeModel": "", ...}.
public enum LocalSettings {
    public enum Key: String, CaseIterable, Sendable {
        case deepSeek = "DEEPSEEK_API_KEY"
        case openAI = "OPENAI_API_KEY"
        case gemini = "GEMINI_API_KEY"
        case claude = "ANTHROPIC_API_KEY"
        case glm = "GLM_API_KEY"
        case elevenLabs = "ELEVENLABS_API_KEY"
        public var fileProperty: String {
            switch self {
            case .deepSeek: "DeepSeekApiKey"
            case .openAI: "OpenAIApiKey"
            case .gemini: "GeminiApiKey"
            case .claude: "ClaudeApiKey"
            case .glm: "GLMApiKey"
            case .elevenLabs: "ElevenLabsApiKey"
            }
        }
    }

    /// Every field a new settings file starts with, all empty except the provider.
    public static let template: String = {
        var lines = ["  \"Provider\": \"deepseek\""]
        for provider in Provider.allCases {
            lines.append("  \"\(provider.key.fileProperty)\": \"\"")
            lines.append("  \"\(provider.modelProperty)\": \"\"")
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n}\n"
    }()

    /// A plain text setting: environment variable first, then the settings file.
    public static func text(variable name: String, property: String,
                            environment values: [String: String] = ProcessInfo.processInfo.environment, file: URL? = settingsFile()) -> String {
        if let value = values[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        guard let file, let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return (object[property] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// F2L_PROVIDER or "Provider" (deepseek, openai, gemini, claude, glm; "chatgpt" and "anthropic" also work).
    public static func provider(file: URL? = settingsFile()) -> Provider {
        let value = text(variable: "F2L_PROVIDER", property: "Provider", file: file).lowercased()
        switch value {
        case "chatgpt", "gpt": return .openAI
        case "anthropic": return .claude
        case "zhipu", "chatglm": return .glm
        default: return Provider(rawValue: value) ?? .deepSeek
        }
    }

    /// "<Name>Model" from the settings file, or empty for the provider's default.
    public static func model(for provider: Provider, file: URL? = settingsFile()) -> String {
        text(variable: "F2L_MODEL_\(provider.rawValue.uppercased())", property: provider.modelProperty, file: file)
    }

    /// Writes the chosen provider into the settings file in use (creating it from the template), keeping every key.
    @discardableResult
    public static func setProvider(_ provider: Provider, file: URL? = nil) -> Bool {
        update(file ?? prepareFile()) { $0["Provider"] = provider.rawValue }
    }

    /// Saves a provider's key from Settings into the settings file in use; an empty value removes it.
    @discardableResult
    public static func setKey(_ key: Key, _ value: String, file: URL? = nil) -> Bool {
        update(file ?? prepareFile()) { $0[key.fileProperty] = value.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Changes one settings file, keeping everything else in it, readable only by this user (it can hold keys).
    private static func update(_ url: URL, _ change: (inout [String: Any]) -> Void) -> Bool {
        var object = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        change(&object)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              (try? data.write(to: url, options: .atomic)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    public static var userFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("F2L", isDirectory: true).appendingPathComponent("local.settings.json")
    }

    /// The first settings file that exists, or nil.
    public static func settingsFile(startingAt start: URL = Bundle.main.bundleURL, userFile: URL = userFile) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: userFile.path) { return userFile }
        var directory = start.standardizedFileURL
        while directory.path != "/" {
            if fm.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                for relative in ["local.settings.json", "Windows/F2L.Windows/local.settings.json"] {
                    let candidate = directory.appendingPathComponent(relative)
                    if fm.fileExists(atPath: candidate.path) { return candidate }
                }
            }
            directory = directory.deletingLastPathComponent()
        }
        let beside = start.standardizedFileURL.deletingLastPathComponent().appendingPathComponent("local.settings.json")
        return fm.fileExists(atPath: beside.path) ? beside : nil
    }

    public static func read(_ key: Key, environment: [String: String] = ProcessInfo.processInfo.environment,
                            file: URL? = settingsFile(), keychain: (Key) -> String = keychainValue) -> String {
        if let value = environment[key.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        if let file, let data = try? Data(contentsOf: file),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = (object[key.fileProperty] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        return keychain(key).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `security add-generic-password -s F2L -a DEEPSEEK_API_KEY -w` stores a key here instead of in a file.
    public static func keychainValue(_ key: Key) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "F2L",
            kSecAttrAccount as String: key.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Creates an empty settings file to fill in, if none exists yet, and returns the file to show.
    @discardableResult
    public static func prepareFile(_ url: URL? = settingsFile(), userFile: URL = userFile) -> URL {
        if let url { return url }
        let fm = FileManager.default
        try? fm.createDirectory(at: userFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: userFile.path) {
            try? Data(template.utf8).write(to: userFile, options: .withoutOverwriting)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: userFile.path)
        }
        return userFile
    }
}
