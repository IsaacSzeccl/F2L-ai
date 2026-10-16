using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;

namespace F2L.Windows;

internal interface ICoachClient
{
    bool IsConfigured { get; }
    string NotConfigured => Provider.DeepSeek.NotConfigured();
    /// <summary>The provider named to the learner (the setup window says where a plan request goes).</summary>
    string ProviderName => "DeepSeek";
    /// <summary>A text-only starter-plan request; clients that can't make one say the AI isn't set up.</summary>
    Task<StarterPlan> StarterPlanAsync(LearnerProfile profile, CancellationToken cancellationToken) =>
        Task.FromException<StarterPlan>(new CoachRequestException(NotConfigured));
    Task<CoachAnswer> AnswerAsync(string question, IReadOnlyList<(string Role, string Content)> history,
        byte[]? imageBytes, string? imageContentType, CancellationToken cancellationToken);
    /// <summary>A zoomed second look: where <paramref name="label"/> is in <paramref name="jpeg"/>, a crop covering
    /// <paramref name="crop"/> on screen. Null when unsupported, not configured or not found.</summary>
    Task<Rect?> ZoomLocateAsync(string label, string app, byte[] jpeg, Rect crop, CancellationToken cancellationToken) => Task.FromResult<Rect?>(null);
}

/// <summary>The teaching client: one prompt and one answer format, sent to whichever provider is chosen (DeepSeek,
/// ChatGPT, Gemini, GLM through the OpenAI chat format; Claude through the Messages API). Prompt, payload and wording
/// match Sources/CoachCore/CoachClient.swift. Settings are read for every question, so a switch applies at once.</summary>
internal sealed partial class CoachClient(HttpClient? http = null, Func<CoachSettings>? settings = null) : ICoachClient
{
    private static readonly HttpClient SharedHttp = new(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false }) { Timeout = TimeSpan.FromSeconds(45) };
    private static readonly JsonSerializerOptions HistoryJson = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
    private readonly HttpClient _http = http ?? SharedHttp;
    private readonly Func<CoachSettings> _settings = settings ?? CoachSettings.Current;

    /// <summary>A fixed provider and key, for tests and tools.</summary>
    internal CoachClient(HttpClient? http, Func<string> apiKey, Provider provider = Provider.DeepSeek, string? model = null)
        : this(http, () => CoachSettings.Create(provider, model, apiKey())) { }

    internal static readonly string TeachingPrompt = TeachingReply.Style + "\n" + """
        You are F2L, a practical coach that helps people set up and use AI tools and everyday work apps on their own
        computer: AI assistants such as ChatGPT, Gemini, Claude, Grok, DeepSeek, Copilot and Tencent WorkBuddy, and work apps
        such as Notion, Google Workspace, Microsoft 365, Canva, Zoom and Excel. Use plain language and never patronize the learner.
        Teach the tool the learner asks about even when it is not on screen yet: start from where they are, for example opening
        the browser, going to the tool's official website or app store page, signing in, then the first useful feature. Never
        refuse or stop because a different app is in front; mention what the screenshot shows only when it helps the next step.
        When a screenshot is provided, use only what it visibly supports for places on screen. When the message carries a
        checked recipe, follow it: give every one of its steps in order, leave none out, and keep its on-screen names unless
        the screenshot shows a different name for the same control, in which case the screen wins on the name while the recipe
        still sets the order and what must not be left out. When it carries no recipe and you are unsure how a tool works
        today, say so in one short sentence and then either ask one short question or name the tool's official site; never
        invent a menu, a button or a menu path. If no screenshot is provided, say so naturally when screen details matter. You cannot
        control this computer or click buttons. Ask one short clarifying question only when the request genuinely needs more
        context. Return only a JSON
        object with exactly three keys: "reply", "steps" and "target". "reply" must be natural spoken language, without
        markdown, bullet lists, emojis, or URLs. When the task takes more than one action, "reply" is one short sentence
        saying what the steps achieve, and "steps" lists every action in order, one precise action per item, naming the
        exact keys for the learner's computer (Command on macOS, Ctrl on Windows), whether to hold them, and the exact cells,
        menus and buttons, for example ["Click A1.", "Hold Shift and click A4.", "Hold Command and drag from D1 to D4."].
        Otherwise "steps" is an empty list. Start from what the learner has already done: leave out steps that the
        screenshot shows are already done, such as a sidebar or panel that is already open, and steps that Excel
        reports as already selected. When the message says what Excel reports, trust it over the screenshot for which
        cells are selected. Do not mention easy or hard modes. "target" is null unless the screenshot
        clearly shows the place the learner should act on next: a button, tab, menu, icon, field or cell. Then it
        contains integer left, top, right and bottom coordinates from 0 to 1000 and a label that is the control's exact
        visible name or tooltip, written as the screen shows it, in the app's own language (新增 when the app shows 新增, not
        "Add"), such as "Insert" or "Recommended Charts", so the host can find it. Coordinates are
        thousandths of the screenshot and tightly surround the whole visible control. For an Excel cell or range, also
        add "cell" with its address, such as
        {"reply":"Select cell A1.","steps":[],"target":{"cell":"A1","label":"A1","left":120,"top":210,"right":180,"bottom":228}}.
        The host checks cells with Excel where it can. Each step can point at its own place: write that step as
        {"text":"Open the Insert tab.","target":{"left":300,"top":40,"right":350,"bottom":60,"label":"Insert"}} instead
        of a plain string. Give a target for every step whose place is visible, and for the reply whenever it tells the learner
        to act on something visible; never guess a place you cannot see.
        Positions read from a screenshot are approximate; never claim an exact verified match.
        Use short paragraphs with blank lines for longer explanations so the learner can follow the reply.
        """;

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_settings().ApiKey);
    public string NotConfigured => _settings().Provider.NotConfigured();
    public string ProviderName => _settings().Provider.Name();

    public async Task<CoachAnswer> AnswerAsync(
        string question,
        IReadOnlyList<(string Role, string Content)> history,
        byte[]? imageBytes,
        string? imageContentType,
        CancellationToken cancellationToken)
    {
        var current = _settings();
        if (string.IsNullOrWhiteSpace(current.ApiKey)) throw new CoachRequestException(current.Provider.NotConfigured());
        // JSON mode occasionally returns only whitespace. Ask once more without it before giving up.
        CoachAnswer? first;
        try { first = await SendAsync(current, RequestBody(question, history, imageBytes, imageContentType, true, current.Provider, current.Model), cancellationToken); }
        catch (CoachRequestException error) when (error.Message == current.Provider.Unreadable()) { first = null; }
        return first
            ?? await SendAsync(current, RequestBody(question, history, imageBytes, imageContentType, false, current.Provider, current.Model), cancellationToken)
            ?? throw new CoachRequestException(current.Provider.NoReply());
    }

    /// <summary><paramref name="jsonMode"/> asks for a JSON object where the provider supports it; the retry after an
    /// empty reply leaves it off.</summary>
    internal static string RequestBody(string question, IReadOnlyList<(string Role, string Content)> history,
        byte[]? imageBytes, string? imageContentType, bool jsonMode, Provider provider = Provider.DeepSeek, string? model = null, string? systemPrompt = null,
        int? maxTokens = null)
    {
        systemPrompt ??= TeachingPrompt;
        model = string.IsNullOrWhiteSpace(model) ? provider.DefaultModel() : model;
        var past = history.TakeLast(20).Select(message => (object)new
        {
            role = message.Role,
            content = message.Role == "assistant" ? HistoryReply(message.Content) : message.Content,
        }).ToList();
        var image = imageBytes is { Length: > 0 } && !string.IsNullOrWhiteSpace(imageContentType) ? Convert.ToBase64String(imageBytes) : null;
        if (provider == Provider.Claude)
        {
            // Messages API: the system prompt is separate, and the picture goes before the question.
            var content = new List<object>();
            if (image is not null) content.Add(new { type = "image", source = new { type = "base64", media_type = imageContentType, data = image } });
            content.Add(new { type = "text", text = question });
            past.Add(new { role = "user", content });
            return JsonSerializer.Serialize(new Dictionary<string, object>
            {
                ["model"] = model,
                ["max_tokens"] = 4096,
                ["system"] = systemPrompt,
                ["messages"] = past,
                ["output_config"] = new { effort = "low" }, // quick, short teaching replies
                ["fallbacks"] = "default", // answered by another Claude model if this one declines
            });
        }
        var messages = new List<object> { new { role = "system", content = systemPrompt } };
        messages.AddRange(past);
        object userContent = question;
        if (image is not null)
        {
            var imageUrl = $"data:{imageContentType};base64,{image}";
            object picture = provider is Provider.DeepSeek or Provider.OpenAI ? new { url = imageUrl, detail = "high" } : new { url = imageUrl };
            userContent = new object[] { new { type = "text", text = question }, new { type = "image_url", image_url = picture } };
        }
        messages.Add(new { role = "user", content = userContent });

        var payload = new Dictionary<string, object> { ["model"] = model, ["messages"] = messages, ["stream"] = false };
        switch (provider)
        {
            case Provider.DeepSeek:
                payload["thinking"] = new { type = "disabled" };
                payload["temperature"] = 0.2;
                payload["max_tokens"] = maxTokens ?? 650; // short teaching replies; a starter plan asks for more
                break;
            case Provider.OpenAI:
                // Reasoning models only take the default temperature and count their reasoning in this limit.
                payload["max_completion_tokens"] = 4000;
                if (model.StartsWith("gpt-5", StringComparison.Ordinal) || model.StartsWith('o')) payload["reasoning_effort"] = "minimal";
                break;
            case Provider.Glm:
                payload["thinking"] = new { type = "disabled" };
                payload["temperature"] = 0.2;
                payload["max_tokens"] = 2000;
                break;
            default:
                payload["temperature"] = 0.2;
                payload["max_tokens"] = 4000;
                break;
        }
        if (jsonMode) payload["response_format"] = new { type = "json_object" };
        return JsonSerializer.Serialize(payload);
    }

    /// <summary>Earlier replies go back in the JSON shape the model answers in. With plain-text replies in the
    /// history, DeepSeek's JSON mode returns nothing but spaces ("I couldn't form a reply").</summary>
    internal static string HistoryReply(string text) =>
        JsonSerializer.Serialize(new { reply = text, target = (string?)null }, HistoryJson);

    private async Task<CoachAnswer?> SendAsync(CoachSettings current, string payload, CancellationToken cancellationToken)
    {
        var body = await ResponseAsync(current, payload, cancellationToken);
        return ParseResponse(body, current.Provider);
    }

    public async Task<StarterPlan> StarterPlanAsync(LearnerProfile profile, CancellationToken cancellationToken)
    {
        var current = _settings();
        if (string.IsNullOrWhiteSpace(current.ApiKey)) throw new CoachRequestException(current.Provider.NotConfigured());
        var payload = RequestBody(StarterPlan.Question(profile), [], null, null, true, current.Provider, current.Model, StarterPlan.SystemPrompt, 2000);
        var body = await ResponseAsync(current, payload, cancellationToken);
        var text = ResponseText(body, current.Provider) ?? throw new CoachRequestException(current.Provider.NoReply());
        return StarterPlan.Parse(text, current.Provider.Name());
    }

    /// <summary>One short request (about 80 output tokens) asking where a control is in a crop of the window.</summary>
    public async Task<Rect?> ZoomLocateAsync(string label, string app, byte[] jpeg, Rect crop, CancellationToken cancellationToken)
    {
        var current = _settings();
        if (string.IsNullOrWhiteSpace(current.ApiKey) || jpeg.Length == 0) return null;
        try
        {
            var payload = RequestBody(ZoomLocate.Question(label, app), [], jpeg, "image/jpeg", true, current.Provider, current.Model, ZoomLocate.SystemPrompt, 80);
            var body = await ResponseAsync(current, payload, cancellationToken);
            return ResponseText(body, current.Provider) is { } text ? ZoomLocate.Parse(text, crop) : null;
        }
        catch (CoachRequestException) { return null; }
    }

    private async Task<string> ResponseAsync(CoachSettings current, string payload, CancellationToken cancellationToken)
    {
        var provider = current.Provider;
        using var request = new HttpRequestMessage(HttpMethod.Post, provider.Endpoint());
        if (provider == Provider.Claude)
        {
            request.Headers.Add("x-api-key", current.ApiKey.Trim());
            request.Headers.Add("anthropic-version", "2023-06-01");
            request.Headers.Add("anthropic-beta", "server-side-fallback-2026-07-01");
        }
        else request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", current.ApiKey.Trim());
        request.Content = new StringContent(payload, Encoding.UTF8, "application/json");

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new CoachRequestException(provider.TooSlow());
        }
        catch (HttpRequestException exception) when (exception.InnerException is SocketException)
        {
            throw new CoachRequestException(provider.HostUnreachable());
        }
        catch (HttpRequestException)
        {
            throw new CoachRequestException(provider.ConnectionFailed());
        }

        using (response)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            if (!response.IsSuccessStatusCode)
                throw new CoachRequestException(ExplainProviderError((int)response.StatusCode, body, provider, current.Model));
            return body;
        }
    }

    /// <summary>Reads a reply. Null means it was blank or had no "reply", so the caller can ask again.</summary>
    internal static CoachAnswer? ParseResponse(string body, Provider provider = Provider.DeepSeek)
    {
        var text = ResponseText(body, provider);
        return text is null ? null : ReadReply(text, provider);
    }

    private static string? ResponseText(string body, Provider provider)
    {
        string? responseText = null;
        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            if (provider == Provider.Claude)
            {
                // Messages API: content blocks; only the text blocks are the answer.
                if (root.TryGetProperty("stop_reason", out var stop) && stop.ValueKind == JsonValueKind.String && stop.GetString() == "refusal")
                    throw new CoachRequestException(provider.Declined());
                responseText = string.Concat(root.GetProperty("content").EnumerateArray()
                    .Where(block => block.TryGetProperty("type", out var type) && type.GetString() == "text")
                    .Select(block => block.GetProperty("text").GetString()));
            }
            else
            {
                var content = root.GetProperty("choices")[0].GetProperty("message").GetProperty("content");
                if (content.ValueKind == JsonValueKind.String)
                    responseText = content.GetString();
                if (content.ValueKind == JsonValueKind.Array)
                {
                    var parts = content.EnumerateArray()
                        .Where(part => part.ValueKind == JsonValueKind.Object &&
                            part.TryGetProperty("text", out var text) && text.ValueKind == JsonValueKind.String)
                        .Select(part => part.GetProperty("text").GetString())
                        .Where(text => !string.IsNullOrWhiteSpace(text));
                    responseText = string.Join(" ", parts).Trim();
                }
            }
        }
        catch (Exception error) when (error is JsonException or KeyNotFoundException or InvalidOperationException or IndexOutOfRangeException)
        {
            throw new CoachRequestException(provider.Unreadable());
        }
        return string.IsNullOrWhiteSpace(responseText) ? null : responseText;
    }

    [GeneratedRegex(@"\A```[A-Za-z]*")] internal static partial Regex FenceStart();
    [GeneratedRegex(@"```\s*\z")] internal static partial Regex FenceEnd();

    /// <summary>The model's message: a JSON object (optionally in a code fence), or plain text when JSON mode was off.</summary>
    internal static CoachAnswer? ReadReply(string text, Provider provider = Provider.DeepSeek)
    {
        var clean = text.Trim();
        if (clean.StartsWith("```", StringComparison.Ordinal))
            clean = FenceEnd().Replace(FenceStart().Replace(clean, ""), "").Trim();
        if (clean.Length == 0) return null;
        if (!clean.StartsWith('{')) return new CoachAnswer(TeachingReply.Clean(clean), null);
        try
        {
            using var answer = JsonDocument.Parse(clean);
            var root = answer.RootElement;
            var reply = root.TryGetProperty("reply", out var replyElement) && replyElement.ValueKind == JsonValueKind.String
                ? replyElement.GetString()?.Trim()
                : null;
            if (string.IsNullOrWhiteSpace(reply)) return null;
            var steps = ParseSteps(root);
            return new CoachAnswer(TeachingReply.Clean(reply), ParseTarget(root), steps.Select(step => step.Text).ToArray(),
                steps.Select(step => step.Target).ToArray());
        }
        catch (JsonException)
        {
            throw new CoachRequestException(provider.Unreadable());
        }
    }

    /// <summary>Up to 12 non-empty steps. Each is a string, or {"text": ..., "target": ...} when the model can see where it happens.</summary>
    private static IReadOnlyList<(string Text, ScreenTarget? Target)> ParseSteps(JsonElement answer)
    {
        if (!answer.TryGetProperty("steps", out var steps) || steps.ValueKind != JsonValueKind.Array) return [];
        var parsed = new List<(string, ScreenTarget?)>();
        foreach (var item in steps.EnumerateArray())
        {
            var text = item.ValueKind == JsonValueKind.String ? item.GetString()
                : item.ValueKind == JsonValueKind.Object && item.TryGetProperty("text", out var value) && value.ValueKind == JsonValueKind.String ? value.GetString()
                : null;
            if (string.IsNullOrWhiteSpace(text)) continue;
            parsed.Add((text.Trim(), item.ValueKind == JsonValueKind.Object ? ParseTarget(item) : null));
            if (parsed.Count == 12) break;
        }
        return parsed;
    }

    /// <summary>Reads <paramref name="owner"/>'s "target": a box in thousandths of the screenshot, or an Excel cell
    /// (a range is named by its first cell) with or without its box.</summary>
    private static ScreenTarget? ParseTarget(JsonElement owner)
    {
        if (!owner.TryGetProperty("target", out var target) || target.ValueKind != JsonValueKind.Object)
            return null;
        var hasBox = TryCoordinate(target, "left", out var left) & TryCoordinate(target, "top", out var top) &
            TryCoordinate(target, "right", out var right) & TryCoordinate(target, "bottom", out var bottom) &&
            right > left && bottom > top && right - left <= 700 && bottom - top <= 700;
        if (target.TryGetProperty("cell", out var cellElement) && cellElement.ValueKind == JsonValueKind.String)
        {
            var text = cellElement.GetString() ?? "";
            var cell = CellReference.Parse(text.Split(':')[0]);
            if (cell is null) return null;
            var label = text.Replace("$", "").ToUpperInvariant();
            return hasBox ? new ScreenTarget(left, top, right, bottom, label, cell.Address) : new ScreenTarget(0, 0, 0, 0, label, cell.Address);
        }
        if (!hasBox) return null;
        var name = target.TryGetProperty("label", out var labelElement) && labelElement.ValueKind == JsonValueKind.String
            ? labelElement.GetString()?.Trim()
            : null;
        return new ScreenTarget(left, top, right, bottom,
            string.IsNullOrWhiteSpace(name) ? "Next step" : name.Length <= 36 ? name : name[..36]);
    }

    private static bool TryCoordinate(JsonElement target, string key, out int value)
    {
        value = 0;
        return target.TryGetProperty(key, out var coordinate) && coordinate.ValueKind == JsonValueKind.Number &&
            coordinate.TryGetInt32(out value) && value is >= 0 and <= 1000;
    }

    private static string ExplainProviderError(int statusCode, string body, Provider provider = Provider.DeepSeek, string? model = null)
    {
        var name = provider.Name();
        model ??= provider.DefaultModel();
        return statusCode switch
        {
            401 or 403 => $"{name} rejected the configured API key ({statusCode}). Paste an active {name} key in Settings (Pip’s ··· menu), then try again.",
            402 => $"{name} reports that the account has no available balance (402). Check the account's API balance, then try again.",
            404 => $"{name} couldn't find the requested model or endpoint (404). F2L is set to {model}; put a model your account can use in {provider.ModelProperty()} in local.settings.json.",
            429 => $"{name} is rate-limiting requests (429). Wait a moment, then try again.",
            503 or 529 => $"{name} is temporarily overloaded ({statusCode}). Wait a moment, then try again.",
            400 or 422 => $"{name} rejected the request ({statusCode}). Check the selected model and request settings, then try again.",
            _ => $"{name} returned an error ({statusCode}). Check the local F2L status and try again.",
        };
    }

}

internal sealed class CoachRequestException(string message) : Exception(message);

internal sealed record CoachAnswer(string Reply, ScreenTarget? Target, IReadOnlyList<string>? Steps = null,
    IReadOnlyList<ScreenTarget?>? StepTargets = null)
{
    internal string Text => TeachingReply.Clean(Reply) + (Steps is { Count: > 0 }
        ? "\n\n" + string.Join("\n", Steps.Select((step, index) => $"{index + 1}. {step}")) : "");

    /// <summary>Where each lesson step points: its own place; else the reply's place when the step names it (or is the
    /// only step); else the thing the step names, found on screen by name. Same as CoachAnswer.placesForSteps on Mac.</summary>
    internal IReadOnlyList<ScreenTarget?> PlacesForSteps => (Steps ?? []).Select((step, index) =>
        StepTargets is { } own && index < own.Count && own[index] is { } mine ? mine
        : Target is { } target && (Steps!.Count == 1 || Mentions(step, target.Label)) ? target
        : NamedPlace.Target(step)).ToList();

    /// <summary>Where a plain reply points: the AI's place, or the thing the reply tells the learner to act on.</summary>
    internal ScreenTarget? PlaceForReply => Target ?? (Steps is { Count: > 0 } ? null : NamedPlace.Target(Reply));

    private static bool Mentions(string step, string label)
    {
        var name = TargetSnap.Normalise(label);
        return !TargetSnap.Generic.Contains(name) && TargetSnap.Normalise(step).Contains(name);
    }
}

internal sealed record ScreenTarget(int Left, int Top, int Right, int Bottom, string Label, string? Cell = null)
{
    /// <summary>Whether the model gave where it is on the screenshot (a cell may come with or without one).</summary>
    internal bool HasBox => Right > Left && Bottom > Top;
}
