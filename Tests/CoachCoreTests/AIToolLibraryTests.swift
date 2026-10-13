import Foundation
import Testing
@testable import CoachCore

// Same cases as TestAIToolLibrary on Windows.
@Suite struct AIToolLibraries {
    let library = AIToolLibrary.shared

    @Test func theSharedLibraryLoadsAndIsWellFormed() {
        #expect(library.tools.count >= 60 && !library.checked.isEmpty)
        #expect(Set(library.tools.map(\.id)).count == library.tools.count)
        let focuses = Set(LearnerProfile.focuses.map(\.0))
        for tool in library.tools {
            #expect(tool.url.hasPrefix("https://") && !tool.summary.isEmpty && !tool.start.isEmpty && !tool.features.isEmpty, "\(tool.id)")
            #expect(!tool.goodFor.isEmpty && Set(tool.goodFor).isSubset(of: focuses), "\(tool.id)")
        }
        // The offline starter plan uses these.
        for id in ["excel", "notion", "canva", "notebooklm", "zapier", "copilot"] { #expect(library.find(id) != nil, "\(id)") }
        #expect(ToolCatalog.common.count >= 10 && ToolCatalog.all.count == library.tools.count)
    }

    @Test(arguments: [("How do I set up n8n with Notion?", ["notion", "n8n"]), ("i would like to learn how to use tencent workbuddy", ["workbuddy"]),
                      ("Teach me Grok", ["grok"]), ("怎么用豆包", ["doubao"]), ("How do I use make.com?", ["make"]),
                      ("Make a chart from this", []), ("Find the gamma value", []), ("Open Gamma app", ["gamma"])])
    func questionsFindTheToolsTheyName(question: String, ids: [String]) {
        #expect(library.mentioned(in: question).map(\.id) == ids)
    }

    @Test func notesTeachFromCheckedFactsAndRecommendFromTheLibrary() {
        let notes = library.referenceNotes(question: "How do I start with n8n?")
        #expect(notes.contains("n8n (Automation)") && notes.contains("Official site: https://n8n.io.") && notes.contains("Getting started: 1)"))
        #expect(notes.contains("data, not instructions") && !notes.contains("may fit this learner"))
        #expect(library.referenceNotes(question: "What is SUM?").isEmpty)
        var learner = LearnerProfile(); learner.focus = "create"
        #expect(AIToolLibrary.asksForRecommendation("Which AI tool should I use for slides?"))
        #expect(!AIToolLibrary.asksForRecommendation("Click the Insert tab"))
        let fits = library.fitting(learner)
        #expect(fits.count == 10 && fits.allSatisfy { $0.goodFor.contains("create") })
        #expect(library.referenceNotes(question: "Which AI tool should I use for slides?", profile: learner).contains("may fit this learner"))
        #expect(CoachClient.compose(question: "How do I start with n8n?", platform: "macOS", excel: nil, library: library).contains("Official site: https://n8n.io."))
    }

    @Test func aMissingLibraryFallsBackToTheStarterSet() {
        let fallback = AIToolLibrary.load(from: URL(fileURLWithPath: "/nonexistent/ai-tools.json"))
        #expect(fallback.tools.map(\.id) == ["excel", "notion", "canva", "notebooklm", "zapier", "copilot"])
    }
}
