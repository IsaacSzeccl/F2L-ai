import Foundation
import Testing
@testable import CoachCore

/// Synthetic data only. These tests never touch the user's real profile.
let starterPlanFixture = #"{"title":"A calmer reporting week","summary":"Make room to review your work.","tools":[{"id":"excel","reason":"Review your weekly figures."},{"id":"notion","reason":"Keep your decisions together."}],"workflow":[{"title":"Choose","detail":"Choose sample figures."},{"title":"Draft","detail":"Draft a short report."},{"title":"Review","detail":"Check every figure yourself."}],"firstPrompt":"Help me draft a weekly report.","source":"spoofed"}"#

@Suite struct LearnerProfiles {
    @Test func normalizesLimitsAndKnownChoices() {
        var p = LearnerProfile(); p.name = "  Alex  "; p.role = String(repeating: "r", count: 140)
        p.goal = String(repeating: "g", count: 700); p.experience = "invalid"; p.focus = "invalid"
        p.existingTools = ["excel", "excel", "untrusted", "canva"]
        let saved = p.normalized
        #expect(saved.name == "Alex" && saved.role.count == 120 && saved.goal.count == 500)
        #expect(saved.experience == "new" && saved.focus == "organize")
        #expect(saved.existingTools == ["canva", "excel"])
    }

    @Test func whatTheyWantToLearnIsTidiedSavedAndSent() throws {
        var p = LearnerProfile(); p.role = "Analyst"; p.focus = "analyze"
        p.learning = [" Pivot tables ", "pivot tables", "", String(repeating: "x", count: 90), "a", "b", "c", "d", "e"]
        let saved = p.normalized
        #expect(saved.learning.count == LearnerProfile.maxLearning)
        #expect(saved.learning[0] == "Pivot tables" && saved.learning[1].count == 80)
        #expect(saved.backgroundJSON.contains(#""learning":["Pivot tables""#))
        // Profiles saved before this field existed still load.
        let old = try JSONDecoder().decode(LearnerProfile.self, from: Data(#"{"name":"A","role":"Ops","goal":"","experience":"some","focus":"build","existingTools":["excel"],"personalizationEnabled":true}"#.utf8))
        #expect(old.role == "Ops" && old.learning.isEmpty && old.existingTools == ["excel"])
        // Their own choices come first, then ideas for their kind of help, then their plan's tools, without repeats.
        var q = LearnerProfile(); q.focus = "analyze"; q.learning = ["My own topic", "Pivot tables"]
        var plan = StarterPlan.draft(for: q); plan.tools = [SuggestedTool(id: "notion", reason: "r")]
        let ideas = LearnerProfile.learningIdeas(for: q, plan: plan)
        #expect(ideas.prefix(2) == ["My own topic", "Pivot tables"] && ideas.last == "Getting started with Notion")
        #expect(ideas.filter { $0 == "Pivot tables" }.count == 1)
        #expect(LearnerProfile.lessonQuestion("Pivot tables").hasSuffix(": Pivot tables"))
    }

    @Test func requiresRoleOrGoalButNotName() {
        var p = LearnerProfile(); p.name = "Alex"; p.role = " \n "
        #expect(!p.isReady)
        p.goal = "Find my next career step"; #expect(p.isReady)
    }

    @Test func savesReloadsAndForgetsBothProfileAndPlan() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(url: directory.appendingPathComponent("profile.json"))
        #expect(!store.load().onboardingComplete)
        var p = LearnerProfile(); p.role = "Operations"; p.name = "Alex"
        let doc = ProfileDocument(profile: p, plan: StarterPlan.draft(for: p), onboardingComplete: true)
        try store.save(doc)
        #expect(ProfileStore(url: store.url).load() == doc)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try store.forget()
        #expect(store.load().onboardingComplete && store.load().profile == nil && store.load().plan == nil)
        #expect(!(try String(contentsOf: store.url, encoding: .utf8)).contains("Operations"))
    }

    @Test func corruptOrFutureFileReturnsWelcomeState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        #expect(!ProfileStore(url: url).load().onboardingComplete)
        var doc = ProfileDocument(onboardingComplete: true); doc.version = 99
        try ProfileStore(url: url).save(doc)
        #expect(!ProfileStore(url: url).load().onboardingComplete)
    }

    @Test func contextIsExplicitBoundedAndCanBeDisabled() throws {
        var p = LearnerProfile(); p.name = "Private name"; p.role = "Operations"; p.goal = "Grow into a team lead role"
        p.experience = "confident"
        let text = CoachClient.compose(question: "How do I sort?", platform: "macOS", excel: nil, profile: p)
        #expect(text.contains("Operations") && text.contains(p.pace))
        #expect(!text.contains(p.name))
        #expect(text.contains("never assume ability from occupation"))
        p.personalizationEnabled = false
        #expect(p.coachingContext.isEmpty)
        #expect(CoachClient.compose(question: "How do I sort?", platform: "macOS", excel: nil, profile: p) ==
                CoachClient.compose(question: "How do I sort?", platform: "macOS", excel: nil))
        // Opting out of future coaching still permits an explicitly requested starter plan.
        #expect(StarterPlan.question(for: p).contains("Operations"))
    }

    @Test func localDraftUsesFocusExistingToolsAndPace() {
        var p = LearnerProfile(); p.goal = "Review reports."; p.focus = "build"
        let draft = StarterPlan.draft(for: p)
        #expect(draft.source == "local" && draft.tools.map(\.id) == ["zapier", "copilot"])
        #expect(draft.workflow[1].detail.contains("one step at a time"))
        #expect(!draft.summary.contains(".."))
        p.existingTools = ["excel"]; p.experience = "confident"
        let tailored = StarterPlan.draft(for: p)
        #expect(tailored.tools.first?.id == "excel")
        #expect(tailored.workflow[1].detail.contains("reusable"))
        #expect(tailored.workflow.last?.detail.contains("Check") == true)
    }

    @Test func parsesFencedPlanAndIgnoresModelSource() throws {
        let plan = try StarterPlan.parse("```json\n" + starterPlanFixture + "\n```", provider: "DeepSeek")
        #expect(plan.source == "DeepSeek" && plan.tools.count == 2 && plan.workflow.count == 3)
    }

    @Test func rejectsInventedToolsEmptyTextAndIncompletePlans() throws {
        for text in ["not JSON", starterPlanFixture.replacingOccurrences(of: "excel", with: "https://untrusted.invalid"),
                     starterPlanFixture.replacingOccurrences(of: "notion", with: "excel"),
                     starterPlanFixture.replacingOccurrences(of: "Choose sample figures.", with: ""),
                     starterPlanFixture.replacingOccurrences(of: "A calmer reporting week", with: "") ] {
            #expect(throws: (any Error).self) { try StarterPlan.parse(text, provider: "test") }
        }
    }

    @Test func allProvidersUseThePlanPromptWithoutImagesOrHistory() throws {
        var p = LearnerProfile(); p.role = "Designer"
        for provider in Provider.allCases {
            let data = try CoachClient.requestBody(question: StarterPlan.question(for: p), history: [], jpeg: nil,
                                                  provider: provider, systemPrompt: StarterPlan.systemPrompt, maxTokens: 2000)
            let body = jsonObject(data)
            let messages = try #require(body["messages"] as? [[String: Any]])
            if provider == .claude {
                #expect(body["system"] as? String == StarterPlan.systemPrompt)
                #expect(messages.count == 1)
            } else {
                #expect(messages.first?["content"] as? String == StarterPlan.systemPrompt)
                #expect(messages.count == 2)
            }
            #expect(!String(decoding: data, as: UTF8.self).contains("image_url") && !String(decoding: data, as: UTF8.self).contains("base64"))
            if provider == .deepSeek { #expect(body["max_tokens"] as? Int == 2000) }
        }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["F2L_LIVE_PROFILE"] == "1"))
struct LiveStarterPlan {
    @Test func selectedProviderBuildsASyntheticPlan() async throws {
        let client = CoachClient()
        try #require(client.isConfigured, "No selected provider key is configured")
        var p = LearnerProfile(); p.role = "Operations coordinator"; p.goal = "Make weekly reporting easier"
        p.experience = "some"; p.focus = "analyze"; p.existingTools = ["excel"]
        let plan = try await client.starterPlan(for: p)
        #expect(plan.source != "local" && plan.tools.count >= 2 && plan.workflow.count >= 3)
        #expect(!plan.firstPrompt.isEmpty)
    }

    @Test func theKindOfHelpComesFromWhatTheyTyped() {
        #expect(LearnerProfile.inferFocus(role: "Operations coordinator", goal: "Weekly sales reports in Excel take me hours") == "analyze")
        #expect(LearnerProfile.inferFocus(role: "Marketing", goal: "Write better client emails") == "create")
        #expect(LearnerProfile.inferFocus(role: "Admin", goal: "Stop doing the same copy and paste every day, automate it") == "build")
        #expect(LearnerProfile.inferFocus(role: "Analyst", goal: "") == "organize" || LearnerProfile.inferFocus(role: "Analyst", goal: "") == "analyze")
        #expect(LearnerProfile.inferFocus(role: "Receptionist", goal: "Keep my week organised") == "organize")
    }

    @Test func planRepliesParseTheSameWayAsTeachingReplies() throws {
        // Closing fence on the same line as the last brace (the old line-dropping lost the brace).
        let fenced = "```json\n{\"title\":\"T\",\"summary\":\"S\",\"tools\":[{\"id\":\"excel\",\"reason\":\"r\"},{\"id\":\"notion\",\"reason\":\"r\"}],\"workflow\":[{\"title\":\"a\",\"detail\":\"b\"},{\"title\":\"c\",\"detail\":\"d\"},{\"title\":\"e\",\"detail\":\"f\"}],\"firstPrompt\":\"go\"}```"
        #expect(try StarterPlan.parse(fenced, provider: "DeepSeek").tools.count == 2)
        // Prose instead of JSON is the plan error, not a raw parser error.
        #expect(throws: CoachRequestError.self) { try StarterPlan.parse("Here is your plan!", provider: "DeepSeek") }
        // An empty duplicate can't hide the good entry for the same tool.
        let duplicate = "{\"title\":\"T\",\"summary\":\"S\",\"tools\":[{\"id\":\"excel\",\"reason\":\"\"},{\"id\":\"excel\",\"reason\":\"r\"},{\"id\":\"notion\",\"reason\":\"r\"}],\"workflow\":[{\"title\":\"a\",\"detail\":\"b\"},{\"title\":\"c\",\"detail\":\"d\"},{\"title\":\"e\",\"detail\":\"f\"}],\"firstPrompt\":\"go\"}"
        #expect(try StarterPlan.parse(duplicate, provider: "DeepSeek").tools.map(\.id) == ["excel", "notion"])
    }

    @Test func draftsKeepAcronymsAndNames() {
        #expect(StarterPlan.inSentence("Make weekly reporting easier") == "make weekly reporting easier")
        #expect(StarterPlan.inSentence("KPI dashboard for my team") == "KPI dashboard for my team")
        #expect(StarterPlan.inSentence("I need faster reports") == "I need faster reports")
        #expect(StarterPlan.inSentence("Excel reports take hours") == "Excel reports take hours")
        var p = LearnerProfile(); p.role = "IT support"
        #expect(StarterPlan.draft(for: p).summary.contains("IT support work"))
    }
}
