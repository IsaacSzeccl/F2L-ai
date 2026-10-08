import Foundation

/// The AI services F2L can teach with. Pick one with "Provider" in local.settings.json (or Pip's menu); each has its
/// own key and an optional model override ("<Name>Model"). Mirrors Windows/F2L.Windows/Providers.cs.
public enum Provider: String, CaseIterable, Sendable {
    case deepSeek = "deepseek"
    case openAI = "openai"
    case gemini = "gemini"
    case claude = "claude"
    case glm = "glm"

    public var name: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAI: "ChatGPT"
        case .gemini: "Gemini"
        case .claude: "Claude"
        case .glm: "GLM"
        }
    }

    /// Used when "<Name>Model" is empty. Each can be changed in local.settings.json without rebuilding.
    public var defaultModel: String {
        switch self {
        case .deepSeek: "deepseek-flash"
        case .openAI: "gpt-5-mini"
        case .gemini: "gemini-2.5-flash"
        case .claude: "claude-opus-5-5"
        case .glm: "glm-4.5v"
        }
    }

    public var endpoint: URL {
        switch self {
        case .deepSeek: URL(string: "https://api.deepseek.com/chat/completions")!
        case .openAI: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .claude: URL(string: "https://api.anthropic.com/v1/messages")!
        case .glm: URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
        }
    }

    public var key: LocalSettings.Key {
        switch self {
        case .deepSeek: .deepSeek
        case .openAI: .openAI
        case .gemini: .gemini
        case .claude: .claude
        case .glm: .glm
        }
    }

    /// The settings-file property that overrides the model, e.g. "ClaudeModel".
    public var modelProperty: String {
        switch self {
        case .deepSeek: "DeepSeekModel"
        case .openAI: "OpenAIModel"
        case .gemini: "GeminiModel"
        case .claude: "ClaudeModel"
        case .glm: "GLMModel"
        }
    }

    /// Everything except Claude speaks the OpenAI chat-completions format.
    public var openAICompatible: Bool { self != .claude }

    // MARK: - What the learner is told (same wording on Windows)

    public func notConfigured() -> String {
        "\(name) isn't configured. Put an active key in \(key.fileProperty) in local.settings.json (Settings shows where it is), then try again."
    }
    public func noReply() -> String { "\(name) sent back an empty reply. Please ask again." }
    public func unreadable() -> String { "\(name) returned a response F2L couldn't read. Please try again." }
    public func tooSlow() -> String { "\(name) took too long to respond. Check your connection and try again." }
    public func hostUnreachable() -> String { "F2L couldn't connect to \(endpoint.host ?? name). Check your internet connection or firewall." }
    public func connectionFailed() -> String { "F2L couldn't connect to \(name). Check your internet connection and try again." }
    public func declined() -> String { "\(name) declined to answer that. Try asking in a different way." }
}

/// The provider, model and key a request uses, read fresh for every question so a switch takes effect at once.
public struct CoachSettings: Sendable {
    public var provider: Provider
    public var model: String
    public var apiKey: String

    public init(provider: Provider, model: String? = nil, apiKey: String) {
        self.provider = provider
        let model = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.model = model.isEmpty ? provider.defaultModel : model
        self.apiKey = apiKey
    }

    /// From the environment (F2L_PROVIDER, <PROVIDER>_API_KEY), local.settings.json and the keychain.
    public static func current() -> CoachSettings {
        let provider = LocalSettings.provider()
        return CoachSettings(provider: provider, model: LocalSettings.model(for: provider), apiKey: LocalSettings.read(provider.key))
    }
}
