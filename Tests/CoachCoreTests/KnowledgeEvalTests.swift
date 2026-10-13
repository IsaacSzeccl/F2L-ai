import Foundation
import Testing
@testable import CoachCore

/// One evaluation case: the question as the learner types it, what was in front of them, and what a good answer
/// must contain. Read from Tests/Fixtures/kb-eval.json so the Windows app can score the same set.
struct KBCase: Codable, Sendable {
    var id: String
    var question: String
    var app: String
    var windowTitle: String
    var account: String
    /// The recipe that should be retrieved, or "" when the honest answer is that there is none.
    var expectedRecipe: String
    /// The tool that should be resolved, or "" when the question names none.
    var expectedTool: String
    /// On-screen names a live reply must contain, in this order.
    var requiredLabels: [String]
    /// Claims a live reply must not make.
    var forbidden: [String]
    /// Held out: the scoring is never tuned on these.
    var heldOut: Bool

    var wantsRecipe: Bool { !expectedRecipe.isEmpty }
}

struct KBSet: Codable, Sendable {
    var version: Int
    var cases: [KBCase]

    static func load() throws -> KBSet {
        let url = repository.appendingPathComponent("Tests/Fixtures/kb-eval.json")
        return try JSONDecoder().decode(KBSet.self, from: try Data(contentsOf: url))
    }
}

/// The offline evaluation: retrieval and tool resolution only, no network, so it runs on every test run and the
/// thresholds in docs/plans/KNOWLEDGE_BASE_PLAN.md are enforced rather than remembered.
@Suite struct KnowledgeBaseEvaluation {
    let tools = AIToolLibrary.shared
    let library = RecipeLibrary.shared

    /// What the app would select for one case, exactly as `compose` does it.
    func selection(_ item: KBCase) -> (tools: [AITool], recipes: [Recipe]) {
        let resolved = tools.resolve(question: item.question, app: item.app, windowTitle: item.windowTitle)
        let moment = RecipeContext(question: item.question, app: item.app, windowTitle: item.windowTitle, account: item.account)
        return (resolved, library.select(moment, tools: resolved))
    }

    @Test func theEvaluationSetIsWellFormed() throws {
        let set = try KBSet.load()
        #expect(set.version == 1 && set.cases.count == 30)
        #expect(Set(set.cases.map(\.id)).count == set.cases.count)
        #expect(set.cases.filter(\.heldOut).count == 10)
        for item in set.cases where item.wantsRecipe {
            #expect(library.find(item.expectedRecipe) != nil, "unknown recipe in the evaluation set: \(item.expectedRecipe)")
        }
        for item in set.cases where !item.expectedTool.isEmpty {
            #expect(tools.find(item.expectedTool) != nil, "unknown tool in the evaluation set: \(item.expectedTool)")
        }
        // Every required label is one a recipe really carries, so the live run measures the recipe and not a guess.
        for item in set.cases where item.wantsRecipe {
            let recipe = try #require(library.find(item.expectedRecipe))
            let labels = Set(recipe.steps.map(\.label))
            for label in item.requiredLabels { #expect(labels.contains(label), "\(item.id): \(label) is not in \(recipe.id)") }
        }
    }

    @Test func theRightToolIsResolvedForEveryCase() throws {
        let set = try KBSet.load()
        var wrong: [String] = []
        for item in set.cases {
            let got = selection(item).tools.first?.id ?? ""
            if got != item.expectedTool { wrong.append("\(item.id): wanted \(item.expectedTool.isEmpty ? "none" : item.expectedTool), got \(got.isEmpty ? "none" : got)") }
        }
        #expect(wrong.isEmpty, "tool resolution:\n\(wrong.joined(separator: "\n"))")
    }

    /// Retrieval hit: the expected recipe is in the top two. The plan's threshold is 90%.
    @Test func retrievalFindsTheExpectedRecipe() throws {
        let set = try KBSet.load()
        let wanted = set.cases.filter(\.wantsRecipe)
        var missed: [String] = []
        for item in wanted where !selection(item).recipes.prefix(2).contains(where: { $0.id == item.expectedRecipe }) {
            missed.append("\(item.id): wanted \(item.expectedRecipe), got \(selection(item).recipes.map(\.id))")
        }
        let hit = Double(wanted.count - missed.count) / Double(wanted.count)
        #expect(hit >= 0.9, "retrieval hit \(Int(hit * 100))% (threshold 90%):\n\(missed.joined(separator: "\n"))")
    }

    /// Honest fallback: a question with no recipe retrieves none, so the prompt tells Pip to say it isn't sure.
    /// The plan's threshold is 90%.
    @Test func questionsWithNoRecipeRetrieveNothing() throws {
        let set = try KBSet.load()
        let none = set.cases.filter { !$0.wantsRecipe }
        var leaked: [String] = []
        for item in none {
            let chosen = selection(item).recipes
            if !chosen.isEmpty { leaked.append("\(item.id): got \(chosen.map(\.id))") }
        }
        let honest = Double(none.count - leaked.count) / Double(none.count)
        #expect(honest >= 0.9, "honest fallback \(Int(honest * 100))% (threshold 90%):\n\(leaked.joined(separator: "\n"))")
    }

    /// The held-out cases are scored on their own: if they are much worse than the rest, the scoring was tuned to
    /// the cases rather than to the task.
    @Test func theHeldOutCasesScoreLikeTheRest() throws {
        let set = try KBSet.load()
        func hit(_ items: [KBCase]) -> Double {
            let wanted = items.filter(\.wantsRecipe)
            guard !wanted.isEmpty else { return 1 }
            let found = wanted.filter { item in selection(item).recipes.prefix(2).contains { $0.id == item.expectedRecipe } }
            return Double(found.count) / Double(wanted.count)
        }
        let held = hit(set.cases.filter(\.heldOut)), tuned = hit(set.cases.filter { !$0.heldOut })
        #expect(held >= 0.8, "held-out retrieval \(Int(held * 100))%")
        #expect(held >= tuned - 0.2, "held-out \(Int(held * 100))% is far below the rest at \(Int(tuned * 100))%")
    }

    /// Grounded labels: every name the recipe tells the learner to look for must be one F2L could later find on
    /// screen, and no recipe may point at a name that says nothing ("here", "button"). The plan's threshold is 95%.
    @Test func everyRecipeLabelIsSomethingTheScreenCheckCanLookFor() {
        var vague: [String] = []
        let all = library.recipes.flatMap { recipe in recipe.steps.map { (recipe.id, $0.label) } }
        for (id, label) in all where TargetSnap.isGeneric(label) { vague.append("\(id): \(label)") }
        let grounded = Double(all.count - vague.count) / Double(all.count)
        #expect(grounded >= 0.95, "grounded labels \(Int(grounded * 100))%:\n\(vague.joined(separator: "\n"))")
    }

    /// The whole prompt for each case stays inside a sensible size, so recipes never crowd out the question.
    @Test func theComposedQuestionStaysSmall() throws {
        let set = try KBSet.load()
        for item in set.cases {
            let text = CoachClient.compose(question: item.question, platform: "macOS", excel: nil, app: item.app,
                                           windowTitle: item.windowTitle, library: .shared, recipes: .shared,
                                           account: item.account)
            #expect(text.count < 12_000, "\(item.id) composed to \(text.count) characters")
        }
    }

    /// Prints the table that goes into docs/reports/SPIKE.md. Not a threshold: it records where the run stands.
    @Test func printTheEvaluationScores() throws {
        let set = try KBSet.load()
        let wanted = set.cases.filter(\.wantsRecipe), none = set.cases.filter { !$0.wantsRecipe }
        let hits = wanted.filter { item in selection(item).recipes.prefix(2).contains { $0.id == item.expectedRecipe } }.count
        let top1 = wanted.filter { selection($0).recipes.first?.id == $0.expectedRecipe }.count
        for item in wanted where !selection(item).recipes.prefix(2).contains(where: { $0.id == item.expectedRecipe }) {
            print("  MISS \(item.id): wanted \(item.expectedRecipe), got \(selection(item).recipes.map(\.id))")
        }
        for item in wanted where selection(item).recipes.first?.id != item.expectedRecipe {
            print("  NOT-TOP1 \(item.id): wanted \(item.expectedRecipe), got \(selection(item).recipes.map(\.id))")
        }
        let honest = none.filter { selection($0).recipes.isEmpty }.count
        let rightTool = set.cases.filter { (selection($0).tools.first?.id ?? "") == $0.expectedTool }.count
        print("""
            KB offline evaluation (\(set.cases.count) cases, \(set.cases.filter(\.heldOut).count) held out)
              tool resolved     \(rightTool)/\(set.cases.count)
              retrieval top 1   \(top1)/\(wanted.count)
              retrieval top 2   \(hits)/\(wanted.count)
              honest fallback   \(honest)/\(none.count)
            """)
        #expect(set.cases.count == 30)
    }
}

/// The live evaluation: sends every case through the configured provider and scores the real reply.
///
///   F2L_LIVE_KB=1 scripts/test.sh --filter LiveKnowledgeBase
///
/// Costs real tokens, so it is off by default, like the other live suites.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["F2L_LIVE_KB"] == "1"))
struct LiveKnowledgeBase {
    @Test func everyCaseIsAnsweredFromTheRecipe() async throws {
        let set = try KBSet.load()
        let coach = CoachClient()
        try #require(coach.isConfigured, "no provider key configured")
        let library = RecipeLibrary.shared, tools = AIToolLibrary.shared

        var complete = 0, grounded = 0, honest = 0, invented: [String] = [], withRecipe = 0, withoutRecipe = 0
        for item in set.cases {
            let question = CoachClient.compose(question: item.question, platform: "macOS", excel: nil, app: item.app,
                                               windowTitle: item.windowTitle, library: tools, recipes: library,
                                               account: item.account)
            let answer = try await coach.answer(question: question, history: [], jpeg: nil)
            let recipe = library.find(item.expectedRecipe)
            let check = RecipeReplyCheck.check(answer, recipe: recipe)
            let said = answer.text.lowercased()

            for claim in item.forbidden where said.contains(claim.lowercased()) {
                invented.append("\(item.id) said \"\(claim)\"")
            }
            if item.wantsRecipe {
                withRecipe += 1
                // Step completeness: every required label, in the order the recipe gives them.
                var at = said.startIndex, ordered = true
                for label in item.requiredLabels {
                    guard let found = said.range(of: label.lowercased(), range: at..<said.endIndex) else { ordered = false; break }
                    at = found.upperBound
                }
                if ordered { complete += 1 }
                if check.isGrounded { grounded += 1 }
            } else {
                withoutRecipe += 1
                // Honest fallback: say it isn't certain, or send the learner to the official site.
                let admits = ["not sure", "not certain", "isn't certain", "can't be sure", "official", "http"]
                if admits.contains(where: said.contains) { honest += 1 }
            }
            print("· \(item.id): missing \(check.missing), ungrounded \(check.ungrounded)")
        }
        print("""
            KB live evaluation
              step completeness \(complete)/\(withRecipe)   (threshold 85%)
              grounded labels   \(grounded)/\(withRecipe)   (threshold 95%)
              honest fallback   \(honest)/\(withoutRecipe)  (threshold 90%)
              invented claims   \(invented.count)           (threshold 0 on demo cases)
            """)
        #expect(Double(complete) / Double(withRecipe) >= 0.85)
        #expect(Double(grounded) / Double(withRecipe) >= 0.95)
        #expect(Double(honest) / Double(withoutRecipe) >= 0.9)
        #expect(invented.isEmpty, "\(invented.joined(separator: "\n"))")
    }
}
