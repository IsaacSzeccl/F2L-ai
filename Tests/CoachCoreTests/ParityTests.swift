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
        for setting in ["[\"temperature\"] = 0.2", "[\"max_tokens\"] = maxTokens ?? 650", "[\"stream\"] = false", "thinking\"] = new { type = \"disabled\" }",
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
    }

    @Test func profilePromptAndCatalogMatch() throws {
        let profile = try source("LearnerProfile.cs")
        #expect(try rawString(after: "internal const string SystemPrompt", in: profile) == StarterPlan.systemPrompt)
        // Both apps read the same AI tools library file; Windows embeds it.
        let project = try source("F2L.Windows.csproj")
        #expect(project.contains("Assets/Knowledge/ai-tools.json"))
        let library = try source("AIToolLibrary.cs")
        for word in AIToolLibrary.ambiguous { expectQuoted(word, in: library) }
        #expect(library.contains("@\"" + AIToolLibrary.recommendation.pattern + "\""))
        for option in LearnerProfile.experiences { for value in [option.0, option.1, option.2] { expectQuoted(value, in: profile) } }
        for focus in LearnerProfile.focuses.map(\.0) {
            var learner = LearnerProfile(); learner.focus = focus
            for idea in LearnerProfile.learningIdeas(for: learner) { expectQuoted(idea, in: profile) }
        }
        #expect(profile.contains("\"" + LearnerProfile.lessonQuestion("{topic}") + "\""))
        #expect(profile.contains("Adapt examples to this background, and to what they chose to learn, when relevant."))
    }

    @Test func clickRulesAndScreenNamesMatch() throws {
        let click = try source("ClickWatch.cs")
        for regex in [ClickWatch.notJustAClick, ClickWatch.heldKey, ClickWatch.typing] { #expect(click.contains("@\"" + regex.pattern + "\"")) }
        #expect(click.contains("TimeSpan.FromSeconds(\(TypingWatch.pause))"))
        #expect(click.contains(String(ScreenNames.line(["OK"]).dropLast(2)).replacingOccurrences(of: "\n", with: "\\n")))
        #expect(click.contains("internal const int Limit = \(ScreenNames.limit);"))
    }

    @Test func brandArtworkIsLoadedTheSameWay() throws {
        // Both apps decode squares at most 512 px wide, keep the screen-sized backdrop and let it go after the opening.
        let mac = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/F2L/BrandArtwork.swift"), encoding: .utf8)
        let windows = try source("BrandArtwork.cs")
        #expect(mac.contains("squareLimit = 512") && windows.contains("SquareLimit = 512"))
        #expect(mac.contains("static let landscape = \"Brand/launch-landscape.png\"") && windows.contains("Landscape = \"Brand/launch-landscape.png\""))
        #expect(try source("IntroWindow.cs").contains("BrandArtwork.Forget(BrandArtwork.Landscape)"))
        // The app-icon master is packaged as .icns / .ico, not shipped inside the apps.
        #expect(try source("F2L.Windows.csproj").contains("Exclude=\"Assets/Brand/app-icon.png\""))
    }

    @Test func playfulIdleTimingMatches() throws {
        let view = try source("PipView.xaml.cs")
        // The same 12-second cycle, 6–9 second quiet lead-in, activity order and frame timings as PipPose.playfulFrame.
        for piece in ["var cycle = time / 12_000;", "var delay = 6_000 + (seed * 73 + cycle % 3_000 * 997) % 3_000;",
                      "if (elapsed < 0 || elapsed >= 2_200) return null;", "var activity = (seed % 4 + cycle % 4 * (1 + seed / 4 % 2 * 2)) % 4;",
                      "Sequence((int)elapsed, [0, 1, 2, 3], [350, 650, 650, 550])", "Random.Shared.Next(65_536)"] {
            #expect(view.contains(piece), "PipView.xaml.cs differs: \(piece)")
        }
        #expect(try source("PipSprites.cs").contains("Load(\"playful\")"))
    }

    @Test func zoomedLookMatches() throws {
        let zoom = try source("ZoomLocate.cs")
        #expect(try rawString(after: "internal const string SystemPrompt", in: zoom) == ZoomLocate.systemPrompt)
        #expect(zoom.contains("$\"Find the \\\"{label}\\\" control") && zoom.contains(" control (a button, tab, icon, menu item or field) in this part of the {app} window. Return JSON.\""))
        #expect(zoom.contains("new(\(Int(ZoomLocate.minimum.width)), \(Int(ZoomLocate.minimum.height)))"))
    }

    @Test func stepGoalRulesMatch() throws {
        let goal = try source("StepGoal.cs")
        for regex in [StepGoal.domain, StepGoal.opening, StepGoal.browserWords] { #expect(goal.contains("@\"" + regex.pattern + "\"")) }
        for browser in StepGoal.browsers { expectQuoted(browser, in: goal) }
    }

    @Test func namedPlaceRulesMatch() throws {
        let named = try source("NamedPlace.cs")
        #expect(named.contains("@\"" + NamedPlace.action.pattern + "\""))
        for word in NamedPlace.keys.union(NamedPlace.filler) { expectQuoted(word, in: named) }
    }

    @Test func conversationWordingAndFileMatch() throws {
        let conversation = try source("ConversationSession.cs")
        expectQuoted(ConversationSession.pendingText, in: conversation)
        expectQuoted(ConversationSession.stoppedText, in: conversation)
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
