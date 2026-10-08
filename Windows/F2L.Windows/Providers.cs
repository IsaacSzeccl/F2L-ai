namespace F2L.Windows;

/// <summary>The AI services F2L can teach with. Pick one with "Provider" in local.settings.json (or Pip's menu); each has
/// its own key and an optional model override ("&lt;Name&gt;Model"). Mirrors Sources/CoachCore/Providers.swift.</summary>
internal enum Provider { DeepSeek, OpenAI, Gemini, Claude, Glm }

internal static class Providers
{
    internal static readonly Provider[] All = [Provider.DeepSeek, Provider.OpenAI, Provider.Gemini, Provider.Claude, Provider.Glm];

    internal static string Id(this Provider provider) => provider switch
    {
        Provider.DeepSeek => "deepseek", Provider.OpenAI => "openai", Provider.Gemini => "gemini", Provider.Claude => "claude", _ => "glm",
    };

    internal static string Name(this Provider provider) => provider switch
    {
        Provider.DeepSeek => "DeepSeek", Provider.OpenAI => "ChatGPT", Provider.Gemini => "Gemini", Provider.Claude => "Claude", _ => "GLM",
    };

    /// <summary>Used when "&lt;Name&gt;Model" is empty.</summary>
    internal static string DefaultModel(this Provider provider) => provider switch
    {
        Provider.DeepSeek => "deepseek-flash", Provider.OpenAI => "gpt-5-mini", Provider.Gemini => "gemini-2.5-flash",
        Provider.Claude => "claude-opus-5-5", _ => "glm-4.5v",
    };

    internal static string Endpoint(this Provider provider) => provider switch
    {
        Provider.DeepSeek => "https://api.deepseek.com/chat/completions",
        Provider.OpenAI => "https://api.openai.com/v1/chat/completions",
        Provider.Gemini => "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        Provider.Claude => "https://api.anthropic.com/v1/messages",
        _ => "https://open.bigmodel.cn/api/paas/v4/chat/completions",
    };

    /// <summary>The environment variable (and Credential Manager name) holding the key.</summary>
    internal static string KeyVariable(this Provider provider) => provider switch
    {
        Provider.DeepSeek => "DEEPSEEK_API_KEY", Provider.OpenAI => "OPENAI_API_KEY", Provider.Gemini => "GEMINI_API_KEY",
        Provider.Claude => "ANTHROPIC_API_KEY", _ => "GLM_API_KEY",
    };

    internal static string KeyProperty(this Provider provider) => provider switch
    {
        Provider.DeepSeek => "DeepSeekApiKey", Provider.OpenAI => "OpenAIApiKey", Provider.Gemini => "GeminiApiKey",
        Provider.Claude => "ClaudeApiKey", _ => "GLMApiKey",
    };

    internal static string ModelProperty(this Provider provider) => provider switch
    {
        Provider.DeepSeek => "DeepSeekModel", Provider.OpenAI => "OpenAIModel", Provider.Gemini => "GeminiModel",
        Provider.Claude => "ClaudeModel", _ => "GLMModel",
    };

    internal static string Host(this Provider provider) => new Uri(provider.Endpoint()).Host;

    /// <summary>"deepseek", "openai"/"chatgpt", "gemini", "claude"/"anthropic", "glm"/"zhipu"; anything else is DeepSeek.</summary>
    internal static Provider Parse(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "openai" or "chatgpt" or "gpt" => Provider.OpenAI,
        "gemini" => Provider.Gemini,
        "claude" or "anthropic" => Provider.Claude,
        "glm" or "zhipu" or "chatglm" => Provider.Glm,
        _ => Provider.DeepSeek,
    };

    // What the learner is told (same wording on Mac).
    internal static string NotConfigured(this Provider p) =>
        $"{p.Name()} isn't configured. Put an active key in {p.KeyProperty()} in local.settings.json (Settings shows where it is), then try again.";
    internal static string NoReply(this Provider p) => $"{p.Name()} sent back an empty reply. Please ask again.";
    internal static string Unreadable(this Provider p) => $"{p.Name()} returned a response F2L couldn't read. Please try again.";
    internal static string TooSlow(this Provider p) => $"{p.Name()} took too long to respond. Check your connection and try again.";
    internal static string HostUnreachable(this Provider p) => $"F2L couldn't connect to {p.Host()}. Check your internet connection or firewall.";
    internal static string ConnectionFailed(this Provider p) => $"F2L couldn't connect to {p.Name()}. Check your internet connection and try again.";
    internal static string Declined(this Provider p) => $"{p.Name()} declined to answer that. Try asking in a different way.";
}

/// <summary>The provider, model and key a request uses, read fresh for every question so a switch applies at once.</summary>
internal sealed record CoachSettings(Provider Provider, string Model, string ApiKey)
{
    internal static CoachSettings Create(Provider provider, string? model, string apiKey) =>
        new(provider, string.IsNullOrWhiteSpace(model) ? provider.DefaultModel() : model.Trim(), apiKey);

    internal static CoachSettings Current()
    {
        var provider = Providers.Parse(CredentialStore.ReadText("F2L_PROVIDER", "Provider"));
        return Create(provider, CredentialStore.ReadText($"F2L_MODEL_{provider.Id().ToUpperInvariant()}", provider.ModelProperty()),
            CredentialStore.Read(provider.KeyVariable()));
    }
}
