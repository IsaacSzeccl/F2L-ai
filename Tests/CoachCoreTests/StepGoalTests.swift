import Testing
@testable import CoachCore

// Same cases as TestStepGoals on Windows.
@Suite struct StepGoals {
    @Test func stepsNameWhatTheyGetTo() {
        #expect(StepGoal.of("Open your browser, such as Safari or Chrome.") == .browser)
        #expect(StepGoal.of("Open Safari.") == .browser)
        #expect(StepGoal.of("Open Excel.") == .app(["excel"]))
        #expect(StepGoal.of("Go to chatgpt.com and click Sign up.") == .site(["chatgpt.com", "chatgpt"]))
        #expect(StepGoal.of("Open notion.so in your browser and sign in.", library: .shared) == .site(["notion.so", "notion"]))
        #expect(StepGoal.of("Go to gemini.google.com.", library: .shared) == .site(["gemini.google.com", "gemini", "gemini"]))
        #expect(StepGoal.of("Open the Insert tab.") == nil)
        #expect(StepGoal.of("Click New page in the left sidebar.") == nil)
    }

    @Test func theAppInFrontShowsTheGoalReached() {
        #expect(StepGoal.browser.isMet(app: "Google Chrome", title: "New Tab") && !StepGoal.browser.isMet(app: "Terminal", title: "zsh"))
        #expect(StepGoal.app(["excel"]).isMet(app: "Microsoft Excel", title: "Book1"))
        let chat = StepGoal.of("Go to chatgpt.com")!
        #expect(chat.isMet(app: "Safari", title: "ChatGPT") && !chat.isMet(app: "Safari", title: "Google"))
        #expect(!chat.isMet(app: "Notes", title: "chatgpt ideas")) // only in a browser
    }
}
