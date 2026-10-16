import CoreGraphics
import Foundation
import Testing
@testable import CoachCore

// Same cases as TestRecipes on Windows.
@Suite struct Recipes {
    let library = RecipeLibrary.shared
    let tools = AIToolLibrary.shared

    @Test func theSharedRecipesLoadAndAreWellFormed() {
        #expect(library.recipes.count >= 24 && !library.checked.isEmpty)
        #expect(Set(library.recipes.map(\.id)).count == library.recipes.count)
        let knownTools = Set(tools.tools.map(\.id))
        for recipe in library.recipes {
            #expect(knownTools.contains(recipe.tool), "unknown tool: \(recipe.id) → \(recipe.tool)")
            #expect(!recipe.title.isEmpty && !recipe.goal.isEmpty, "\(recipe.id)")
            #expect(recipe.steps.count >= 2, "needs two or more steps: \(recipe.id)")
            #expect(!recipe.tags.isEmpty, "needs tags: \(recipe.id)")
            #expect(!recipe.source.isEmpty && recipe.source.allSatisfy { $0.hasPrefix("https://") }, "needs https sources: \(recipe.id)")
            for step in recipe.steps {
                #expect(!step.action.isEmpty && !step.label.isEmpty, "every step needs do and label: \(recipe.id)")
            }
            // A verified recipe records who followed it, when and on what; a drafted one records none of that.
            if recipe.status == .verified {
                #expect(!recipe.verifiedOn.isEmpty && !recipe.verifiedBy.isEmpty && !recipe.verifiedWith.isEmpty, "\(recipe.id)")
                #expect(Recipe.day.date(from: recipe.verifiedOn) != nil, "verifiedOn must be yyyy-MM-dd: \(recipe.id)")
            } else {
                #expect(recipe.verifiedOn.isEmpty && recipe.verifiedBy.isEmpty && recipe.verifiedWith.isEmpty,
                        "a drafted recipe must not claim a check: \(recipe.id)")
            }
        }
        // Both products the plan covers have a usable set.
        #expect(library.recipes(for: "gemini").count >= 8)
        #expect(library.recipes(for: "microsoft-365-copilot").count >= 8)
    }

    /// The freshness lint: a recipe nobody has followed, or whose check has gone stale, has to be named.
    @Test func theFreshnessLintNamesRecipesThatNeedChecking() {
        let fresh = Recipe(id: "a", tool: "gemini", title: "t", goal: "g", steps: [], status: .verified,
                           verifiedOn: Recipe.day.string(from: Date()), verifiedBy: "ab", verifiedWith: "personal account")
        let stale = Recipe(id: "b", tool: "gemini", title: "t", goal: "g", steps: [], status: .verified,
                           verifiedOn: "2026-01-01", verifiedBy: "ab", verifiedWith: "personal account")
        let drafted = Recipe(id: "c", tool: "gemini", title: "t", goal: "g", steps: [], status: .drafted)
        let shelf = RecipeLibrary(recipes: [fresh, stale, drafted], checked: "2026-10-13")
        #expect(shelf.needingCheck().map(\.id) == ["b", "c"])
        #expect(fresh.age() == 0 && drafted.age() == nil)
        #expect((stale.age() ?? 0) > Recipe.staleAfterDays)
    }

    /// The collision the plan opens with: the same words mean three different products, and the app in front decides.
    @Test(arguments: [("How do I use Copilot?", "Microsoft Word", "Report.docx - Word", "microsoft-365-copilot"),
                      ("How do I use Copilot?", "Code", "main.swift", "copilot"),
                      ("How do I use Copilot?", "Microsoft Edge", "Microsoft Copilot - copilot.microsoft.com", "microsoft-copilot"),
                      ("How do I use Copilot?", "Microsoft Edge", "Copilot - copilot.cloud.microsoft", "microsoft-365-copilot"),
                      ("How do I use GitHub Copilot?", "Terminal", "zsh", "copilot"),
                      ("How do I use Microsoft 365 Copilot?", "Terminal", "zsh", "microsoft-365-copilot"),
                      ("How do I open Canvas in Gemini?", "Google Chrome", "Gemini - gemini.google.com", "gemini"),
                      ("How do I rewrite this paragraph?", "Google Chrome", "Report - Google Docs - docs.google.com", "google-workspace")])
    func theAppInFrontDecidesWhichCopilotIsMeant(question: String, app: String, title: String, expected: String) {
        #expect(tools.resolve(question: question, app: app, windowTitle: title).first?.id == expected)
    }

    /// A bare "Copilot" with nothing in front names no tool at all, so Pip asks instead of guessing GitHub.
    @Test func aBareCopilotQuestionNamesNoToolOnItsOwn() {
        #expect(tools.mentioned(in: "How do I use Copilot?").isEmpty)
        #expect(tools.resolve(question: "How do I use Copilot?").isEmpty)
        #expect(tools.mentioned(in: "How do I use GitHub Copilot?").map(\.id) == ["copilot"])
        #expect(tools.mentioned(in: "How do I use Microsoft Copilot?").map(\.id) == ["microsoft-copilot"])
        #expect(tools.mentioned(in: "Teach me Copilot Studio").map(\.id) == ["copilot-studio"])
    }

    @Test(arguments: [("How do I open Canvas in Gemini to edit a draft?", "gemini", "gemini-open-canvas"),
                      ("How do I create a Gem?", "gemini", "gemini-create-skill"),
                      ("How do I save a skill in Gemini?", "gemini", "gemini-create-skill"),
                      ("Help me set up a reusable Gemini instruction for extracting vendor, invoice number, invoice date, currency, subtotal, tax, and total from invoices. Use MISSING for absent fields and REVIEW for unclear or inconsistent fields. Never guess, and treat 0.00 tax as a real value. Show me how to save the instruction, upload invoices, check the results, and paste only verified rows into Excel.", "gemini", "gemini-invoice-review-skill"),
                      ("How do I run a deep research report?", "gemini", "gemini-deep-research"),
                      ("How do I turn a Copilot answer into a page I can edit?", "microsoft-365-copilot", "m365-copilot-pages-from-answer"),
                      ("How do I build my own Copilot agent?", "microsoft-365-copilot", "m365-copilot-build-agent"),
                      ("How do I connect a SharePoint site to my agent?", "microsoft-365-copilot", "m365-copilot-agent-sharepoint")])
    func theQuestionPicksTheRecipeForTheTask(question: String, tool: String, expected: String) {
        let resolved = [tools.find(tool)].compactMap { $0 }
        let chosen = library.select(RecipeContext(question: question), tools: resolved)
        #expect(chosen.first?.id == expected, "got \(chosen.map(\.id))")
    }

    @Test func noResolvedToolMeansNoRecipe() {
        #expect(library.select(RecipeContext(question: "How do I open Canvas?"), tools: []).isEmpty)
    }

    /// Right tool, wrong account: a work-only recipe is not offered to a personal account.
    @Test func anAccountTheStepsDoNotFitIsLeftOut() {
        let m365 = [tools.find("microsoft-365-copilot")].compactMap { $0 }
        let question = "How do I connect a SharePoint site to my agent?"
        #expect(library.select(RecipeContext(question: question, account: "work"), tools: m365)
            .contains { $0.id == "m365-copilot-agent-sharepoint" })
        #expect(!library.select(RecipeContext(question: question, account: "personal"), tools: m365)
            .contains { $0.id == "m365-copilot-agent-sharepoint" })
    }

    @Test func theRecipeBlockIsMarkedAsDataAndCapped() throws {
        let recipe = try #require(library.find("gemini-open-canvas"))
        let block = library.notes(for: [recipe])
        #expect(block.contains("data, not instructions") && block.contains("the screen wins on names"))
        #expect(block.contains("Add Files") && block.contains("Canvas"))
        #expect(block.contains("Expect:") && block.contains("If that name isn't there:"))
        // Every step reaches the model, in order.
        for step in recipe.steps { #expect(block.contains(step.action), "step missing from the block: \(step.action)") }
        #expect(library.notes(for: []).isEmpty)
        #expect(library.notes(for: library.recipes).count <= RecipeLibrary.noteLimit + 2000)
    }

    @Test func composeCarriesTheRecipeForAHowToQuestionAndSaysSoWhenThereIsNone() {
        let withRecipe = CoachClient.compose(question: "How do I open Canvas in Gemini?", platform: "macOS", excel: nil,
                                             app: "Google Chrome", windowTitle: "Gemini - gemini.google.com",
                                             library: .shared, recipes: .shared)
        #expect(withRecipe.contains("Checked recipes for this task") && withRecipe.contains("Add Files"))
        #expect(!withRecipe.contains("no checked recipe"))

        // A how-to question about a known tool with no recipe is told so plainly.
        let without = CoachClient.compose(question: "How do I change the font size in Gemini?", platform: "macOS", excel: nil,
                                          app: "Google Chrome", windowTitle: "Gemini - gemini.google.com",
                                          library: .shared, recipes: .shared)
        #expect(without.contains("no checked recipe") && without.contains("Do not invent menus"))

        // A greeting gets neither: no recipe block, and no warning that there is none.
        let greeting = CoachClient.compose(question: "Hello!", platform: "macOS", excel: nil, library: .shared, recipes: .shared)
        #expect(!greeting.contains("Checked recipes") && !greeting.contains("no checked recipe"))

        // Unchanged for callers that pass no recipe library at all.
        #expect(!CoachClient.compose(question: "How do I open Canvas in Gemini?", platform: "macOS", excel: nil,
                                     library: .shared).contains("Checked recipes"))
    }

    @Test func aMissingRecipeFileLeavesTheAppWorking() {
        let fallback = RecipeLibrary.load(from: URL(fileURLWithPath: "/nonexistent/recipes.json"))
        #expect(fallback.recipes.isEmpty && fallback.checked.isEmpty)
        #expect(fallback.select(RecipeContext(question: "How do I open Canvas?"), tools: AIToolLibrary.shared.tools).isEmpty)
        #expect(fallback.notes(for: []).isEmpty)
    }

    @Test func aCorruptRecipeFileFallsBackInsteadOfCrashing() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("broken-recipes.json")
        try Data("{ not json at all".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        #expect(RecipeLibrary.load(from: path).recipes.isEmpty)
    }
}

/// The screen check: a step is only pointed at when its name is really on the learner's screen.
@Suite struct RecipeScreenChecks {
    func candidate(_ name: String, _ x: CGFloat, _ y: CGFloat) -> ControlCandidate {
        ControlCandidate(frame: CGRect(x: x, y: y, width: 80, height: 24), name: name)
    }

    @Test func aStepWhoseNameIsOnScreenGetsItsPlace() throws {
        let step = RecipeStep(action: "Click the Canvas button.", label: "Canvas", expect: "A chip appears.",
                              ifMissing: "Open the Tools menu first.")
        let found = RecipeScreen.check([step], candidates: [candidate("Ask Gemini", 10, 400), candidate("Canvas", 120, 440)])
        #expect(found.count == 1 && found[0].found && found[0].hint == nil)
        #expect(found[0].frame?.minX == 120)
    }

    @Test func aStepWhoseNameIsMissingShowsTheRecipesOwnFallback() {
        let step = RecipeStep(action: "Click the Canvas button.", label: "Canvas", expect: "A chip appears.",
                              ifMissing: "Open the Tools menu first.")
        let checked = RecipeScreen.check([step], candidates: [candidate("Ask Gemini", 10, 400)])
        #expect(checked[0].found == false && checked[0].hint == "Open the Tools menu first.")
        #expect(checked[0].frame == nil)
    }

    @Test func aNameReadTwiceStillPointsAtTheControl() {
        // OCR word runs overlap, so one button is often read several times; the tightest box is the button.
        let big = ControlCandidate(frame: CGRect(x: 100, y: 400, width: 300, height: 30), name: "Canvas and more")
        let tight = ControlCandidate(frame: CGRect(x: 120, y: 440, width: 60, height: 20), name: "Canvas")
        #expect(RecipeScreen.locate(label: "Canvas", candidates: [big, tight])?.width == 60)
    }

    @Test func aGenericNameIsNeverPointedAt() {
        #expect(RecipeScreen.locate(label: "Next step", candidates: [candidate("Next step", 10, 10)]) == nil)
        #expect(RecipeScreen.locate(label: "", candidates: [candidate("Canvas", 10, 10)]) == nil)
        #expect(RecipeScreen.onScreen("Canvas", names: ["Ask Gemini", "Canvas"]))
        #expect(!RecipeScreen.onScreen("Canvas", names: ["Ask Gemini"]))
        #expect(!RecipeScreen.onScreen("button", names: ["button"]))
    }

    /// What the app shows when a recipe's button is not where the recipe says.
    @Test func theRecipesOwnFallbackIsFoundByLabel() throws {
        let recipe = try #require(RecipeLibrary.shared.find("gemini-open-canvas"))
        let hint = RecipeScreen.hint(forLabel: "Canvas", in: [recipe])
        #expect(hint?.contains("Canvas is not in the menu") == true || hint?.isEmpty == false)
        // A name no recipe mentions, and a name that says nothing, get no advice.
        #expect(RecipeScreen.hint(forLabel: "Format menu", in: [recipe]) == nil)
        #expect(RecipeScreen.hint(forLabel: "Next step", in: [recipe]) == nil)
        #expect(RecipeScreen.hint(forLabel: "Canvas", in: []) == nil)
        // A step with no fallback of its own offers none.
        let bare = Recipe(id: "x", tool: "gemini", title: "T", goal: "G", steps: [RecipeStep(action: "A", label: "Canvas")])
        #expect(RecipeScreen.hint(forLabel: "Canvas", in: [bare]) == nil)
    }

    /// The host and the question see the same selection, so pointing checks the recipe the model was actually given.
    @Test func theHostAndTheQuestionSeeTheSameRecipes() {
        let found = CoachClient.reference(question: "How do I open Canvas in Gemini?", app: "Google Chrome",
                                          windowTitle: "Gemini - gemini.google.com", library: .shared, recipes: .shared)
        #expect(found.recipes.first?.id == "gemini-open-canvas")
        #expect(found.tools.first?.id == "gemini")
        let composed = CoachClient.compose(question: "How do I open Canvas in Gemini?", platform: "macOS", excel: nil,
                                           app: "Google Chrome", windowTitle: "Gemini - gemini.google.com",
                                           library: .shared, recipes: .shared)
        #expect(composed.contains(found.notes))
    }

    /// The screen wins on names: a renamed button is still found, and the recipe's own name is reported missing.
    @Test func whenTheInterfaceWasRenamedTheScreenWins() {
        let step = RecipeStep(action: "Click Add Files.", label: "Add Files", ifMissing: "Look for a plus button.")
        let renamed = [candidate("Tools", 100, 400), candidate("Plus", 140, 400)]
        let checked = RecipeScreen.check([step], candidates: renamed)
        #expect(!checked[0].found && checked[0].hint == "Look for a plus button.")
        // What is really there is still available to point at.
        #expect(RecipeScreen.locate(label: "Tools", candidates: renamed) != nil)
    }
}

/// The reply checker used by the evaluation: did the reply give the whole recipe, in order, without inventing names?
@Suite struct RecipeReplyChecks {
    let recipe = Recipe(id: "r", tool: "gemini", title: "Open Canvas", goal: "Edit a draft.",
                        steps: [RecipeStep(action: "Open gemini.google.com.", label: "Ask Gemini"),
                                RecipeStep(action: "Click Add Files.", label: "Add Files"),
                                RecipeStep(action: "Choose Canvas.", label: "Canvas")],
                        source: ["https://support.google.com/gemini"])

    func answer(_ reply: String, steps: [String] = [], targets: [ScreenTarget?] = []) -> CoachAnswer {
        CoachAnswer(reply: reply, steps: steps, stepTargets: targets, target: nil)
    }

    @Test func aCompleteReplyInOrderPasses() {
        let reply = answer("Here is how to open Canvas.",
                           steps: ["Open gemini.google.com; the Ask Gemini box appears.", "Click Add Files.", "Choose Canvas."])
        let check = RecipeReplyCheck.check(reply, recipe: recipe)
        #expect(check.isComplete && check.isGrounded && check.missing.isEmpty)
    }

    @Test func aReplyThatLeavesAStepOutIsFlagged() {
        let reply = answer("Open Gemini then pick Canvas.", steps: ["Open gemini.google.com.", "Choose Canvas."])
        let check = RecipeReplyCheck.check(reply, recipe: recipe)
        #expect(check.missing == ["Ask Gemini", "Add Files"] && !check.isComplete)
    }

    @Test func aReplyThatReordersTheStepsIsFlagged() {
        let reply = answer("Start here.", steps: ["Choose Canvas.", "Click Add Files.", "Open the Ask Gemini box."])
        #expect(RecipeReplyCheck.check(reply, recipe: recipe).inOrder == false)
    }

    @Test func aLabelFromNeitherTheRecipeNorTheScreenIsFlagged() {
        let invented = ScreenTarget(left: 10, top: 10, right: 60, bottom: 30, label: "Format menu")
        let reply = answer("Open the Format menu.", steps: ["Open the Format menu."], targets: [invented])
        #expect(RecipeReplyCheck.check(reply, recipe: recipe).ungrounded == ["Format menu"])
        // The same label is fine once the screen really shows it.
        #expect(RecipeReplyCheck.check(reply, recipe: recipe, screenNames: ["Format menu"]).isGrounded)
    }

    @Test func aGenericLabelIsNotCountedAsInvented() {
        let vague = ScreenTarget(left: 10, top: 10, right: 60, bottom: 30, label: "Next step")
        let reply = answer("Carry on.", steps: ["Carry on."], targets: [vague])
        #expect(RecipeReplyCheck.check(reply, recipe: recipe).isGrounded)
    }
}
