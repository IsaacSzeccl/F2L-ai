import Foundation
import Testing
@testable import CoachCore

/// The Windows app can't be compiled on a Mac, so these tests read its C# sources and check that the rules both
/// apps share (prompt, model, messages, patterns) haven't drifted apart.
@Suite struct ParityWithWindows {
    func source(_ name: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent("Windows/F2L.Windows/\(name)"), encoding: .utf8)
    }

    /// The text of the C# raw string literal that follows `marker`, with the closing delimiter's indentation removed.
    func rawString(after marker: String, in text: String) throws -> String {
        let start = try #require(text.range(of: marker))
        let open = try #require(text.range(of: "\"\"\"\n", range: start.upperBound..<text.endIndex))
        let close = try #require(text.range(of: "\"\"\";", range: open.upperBound..<text.endIndex))
        var lines = text[open.upperBound..<close.lowerBound].components(separatedBy: "\n")
        let indent = lines.removeLast().count // the closing line holds only indentation
        return lines.map { String($0.dropFirst(indent)) }.joined(separator: "\n")
    }

    func expectQuoted(_ value: String, in text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(text.contains("\"\(value)\""), "missing from the C# source: \(value)", sourceLocation: sourceLocation)
    }

    @Test func promptAndProvidersMatch() throws {
        let coach = try source("CoachClient.cs"), providers = try source("Providers.cs")
        #expect(try rawString(after: "internal static readonly string TeachingPrompt", in: coach) + "" ==
                CoachClient.teachingPrompt.replacingOccurrences(of: TeachingReply.style + "\n", with: ""))
        #expect(coach.contains("TeachingPrompt = TeachingReply.Style + \"\\n\" + \"\"\""))
        #expect(try rawString(after: "internal const string Style", in: try source("TeachingReply.cs")) == TeachingReply.style)
        for provider in Provider.allCases {
            for value in [provider.rawValue, provider.name, provider.defaultModel, provider.endpoint.absoluteString,
                          provider.key.rawValue, provider.key.fileProperty, provider.modelProperty] {
                expectQuoted(value, in: providers)
            }
        }
        for setting in ["[\"temperature\"] = 0.2", "[\"max_tokens\"] = 650", "[\"stream\"] = false", "thinking\"] = new { type = \"disabled\" }",
                        "response_format\"] = new { type = \"json_object\" }", "TakeLast(20)", "detail = \"high\"",
                        "[\"max_completion_tokens\"] = 4000", "[\"reasoning_effort\"] = \"minimal\"", "[\"max_tokens\"] = 4096",
                        "new { effort = \"low\" }", "[\"fallbacks\"] = \"default\"", "\"anthropic-version\", \"2023-06-01\"",
                        "\"anthropic-beta\", \"server-side-fallback-2026-07-01\"", "\"x-api-key\""] {
            #expect(coach.contains(setting), "request setting differs: \(setting)")
        }
    }

    /// The Swift wording for GLM, with the provider-specific parts turned into the C# placeholders.
    func template(_ text: String, _ swaps: [(String, String)]) -> String {
        swaps.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    @Test func providerMessagesMatch() throws {
        let providers = try source("Providers.cs"), coach = try source("CoachClient.cs")
        let glm = Provider.glm
        let swaps = [("GLMApiKey", "{p.KeyProperty()}"), (glm.endpoint.host!, "{p.Host()}"), ("GLM", "{p.Name()}")]
        for message in [glm.notConfigured(), glm.noReply(), glm.unreadable(), glm.tooSlow(), glm.hostUnreachable(), glm.connectionFailed(), glm.declined()] {
            expectQuoted(template(message, swaps), in: providers.replacingOccurrences(of: "$\"", with: "\""))
        }
        let explainSwaps = [("GLMApiKey", "{provider.KeyProperty()}"), ("GLMModel", "{provider.ModelProperty()}"), ("MODEL", "{model}"),
                            ("(401)", "({statusCode})"), ("(503)", "({statusCode})"), ("GLM", "{name}")]
        for status in [401, 402, 404, 429, 503] {
            let message = CoachClient.explain(status: status, body: Data(), provider: glm, model: "MODEL")
            expectQuoted(template(message, explainSwaps), in: coach.replacingOccurrences(of: "$\"", with: "\""))
        }
        #expect(coach.contains("$\"{name} rejected the request ({statusCode}). Check the selected model and request settings, then try again.\""))
        #expect(coach.contains("$\"{name} returned an error ({statusCode}). Check the local F2L status and try again.\""))
        #expect(coach.contains("AllowAutoRedirect = false"))
    }

    @Test func patternsMatch() throws {
        let cells = try source("CellReference.cs"), intents = try source("QuestionIntent.cs")
        let teaching = try source("TeachingReply.cs"), coach = try source("CoachClient.cs")
        for (regex, text) in [(CellReference.pattern, cells), (CellReference.pointingVerb, cells), (CellReference.fillerWords, cells),
                              (QuestionIntent.ambiguousPattern, intents), (QuestionIntent.multiPattern, intents),
                              (QuestionIntent.proceduralPattern, intents), (QuestionIntent.quickFactPattern, intents),
                              (TeachingReply.opening, teaching), (TeachingReply.closing, teaching),
                              (CoachClient.fenceStart, coach), (CoachClient.fenceEnd, coach)] {
            #expect(text.contains("@\"\(regex.pattern)\""), "pattern differs: \(regex.pattern)")
        }
        for label in ["Friendly", "Focused", "Thinking", "Curious"] { expectQuoted(label, in: intents) }
    }

    @Test func conversationWordingAndFileMatch() throws {
        let conversation = try source("ConversationSession.cs")
        expectQuoted(ConversationSession.pendingText, in: conversation)
        expectQuoted(ConversationSession.stoppedText, in: conversation)
        for label in ["Thinking", "Stopped", "Couldn't finish", "You", "Pip"] { expectQuoted(label, in: conversation) }
        #expect(conversation.contains("TakeLast(500)") && conversation.contains("TakeLast(20)"))
        #expect(conversation.contains("\"conversation.json\"") && conversation.contains("\".bak\""))
        // Five saved fields: everything else on ConversationEntry must stay out of the file.
        let saved = conversation.components(separatedBy: "\n").filter { $0.contains(" public ") && $0.contains("{ get") && !$0.contains("[JsonIgnore]") }
        #expect(saved.count == 5, "\(saved)")
    }

    @Test func settingsLookupMatches() throws {
        let credentials = try source("CredentialStore.cs"), providers = try source("Providers.cs")
        for key in LocalSettings.Key.allCases {
            let file = key == .elevenLabs ? credentials : providers
            expectQuoted(key.rawValue, in: file)
            expectQuoted(key.fileProperty, in: file)
        }
        #expect(credentials.contains("$\"F2L/{name}\""))
        #expect(credentials.contains("\"Package.swift\"") && credentials.contains("\"local.settings.json\""))
        // The same new-file template: "Provider" first, then each provider's key and model.
        #expect(credentials.contains("\"  \\\"Provider\\\": \\\"deepseek\\\"\"") && credentials.contains("provider.KeyProperty()") && credentials.contains("provider.ModelProperty()"))
        #expect(providers.contains("\"F2L_PROVIDER\"") || credentials.contains("\"F2L_PROVIDER\"") || providers.contains("F2L_PROVIDER"))
    }

    @Test func placementAndPosesMatch() throws {
        let placement = try source("CompanionPlacement.cs"), pip = try source("PipView.xaml.cs")
        for fragment in ["Inflate(30 * scale, 24 * scale)", "var gap = 12 * scale", "Inflate(40 * scale, 40 * scale)", "score += 300 * scale",
                         "* 0.35", "score += 25 * scale", "Inflate(28 * scale, 28 * scale)", "caret.Inflate(40 * scale, 24 * scale)"] {
            #expect(placement.contains(fragment), "placement differs: \(fragment)")
        }
        for fragment in ["[8, 9, 10, 11], [1100, 800, 120, 1400]", "[4, 5, 6, 7], [1000, 800, 120, 800]", "[2, 3, 2, 0], [180, 140, 180, 140]",
                         "[4, 5, 6, 7], [1600, 1000, 120, 1000]", "[8, 9, 10, 11], [1800, 900, 120, 1200]", "[12, 13], [3600, 650]",
                         "[0, 1], [3900, 130]", "[14, 15], [420, 420]", "12 + time / 250 % 2", "10 + time / 170 % 2", "time / 200 % 2"] {
            #expect(pip.contains(fragment), "pose timing differs: \(fragment)")
        }
    }
}
