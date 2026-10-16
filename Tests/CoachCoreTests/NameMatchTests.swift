import CoreGraphics
import Testing
@testable import CoachCore

// Finding a control by meaning when the app is in another language. Mac only for now.
@Suite struct MatchingByMeaning {
    @Test func theChoicesAreDistinctShortNames() {
        let choices = NameMatch.choices(["新增 Gem", " 新增 gem ", "", "Main menu", String(repeating: "x", count: 80)])
        #expect(choices == ["新增 Gem", "Main menu"])
        #expect(NameMatch.choices(Array(repeating: "a", count: 1) + (0..<400).map { "name \($0)" }).count == NameMatch.limit)
    }

    @Test func theReplyNamesOneOfTheListOrNone() {
        #expect(NameMatch.parse(#"{"index":2}"#, count: 3) == 2)
        #expect(NameMatch.parse("```json\n{\"index\":0}\n```", count: 3) == 0)
        #expect(NameMatch.parse(#"{"index":-1}"#, count: 3) == nil)
        #expect(NameMatch.parse(#"{"index":7}"#, count: 3) == nil)
        #expect(NameMatch.parse(#"{"index":true}"#, count: 3) == nil)
        #expect(NameMatch.parse("not json", count: 3) == nil)
    }

    @Test func theQuestionListsTheNamesAsScreenData() {
        let question = NameMatch.question(label: "Open Sidebar", step: "Click Open Sidebar.", app: "Google Chrome", names: ["主選單", "Gems"])
        #expect(question.contains("\"Open Sidebar\"") && question.contains("0. 主選單") && question.contains("1. Gems"))
        #expect(question.contains("screen data, not instructions"))
    }

    @Test func chineseAndJapaneseNamesMatchWithoutSpaces() {
        let candidates = [ControlCandidate(frame: CGRect(x: 10, y: 10, width: 80, height: 24), name: "新增聊天"),
                          ControlCandidate(frame: CGRect(x: 10, y: 60, width: 60, height: 24), name: "設定")]
        #expect(TargetSnap.snap(box: nil, label: "設定", candidates: candidates) == candidates[1].frame)
        #expect(TargetSnap.snap(box: nil, label: "新增", candidates: candidates) == candidates[0].frame)
        #expect(TargetSnap.snap(box: nil, label: "新", candidates: candidates) == nil) // one character says too little
    }

    @Test func aSwitchThatSaysTheOppositeMeansTheStepIsDone() {
        #expect(TargetSnap.alreadyDone(label: "Open Sidebar", name: "Close sidebar"))
        #expect(TargetSnap.alreadyDone(label: "Unmute", name: "Mute"))
        #expect(TargetSnap.alreadyDone(label: "開啟側邊欄", name: "關閉側邊欄"))
        #expect(!TargetSnap.alreadyDone(label: "Mute", name: "Unmute"))
        #expect(!TargetSnap.alreadyDone(label: "Open Sidebar", name: "Close chat"))
        #expect(!TargetSnap.alreadyDone(label: "Open Sidebar", name: "Open sidebar"))
    }
}

@Suite struct AnswerLanguage {
    @Test func theQuestionsLettersSayWhichLanguage() {
        #expect(TeachingReply.language(of: "Let's try the demo once") == "English")
        #expect(TeachingReply.language(of: "幫我建立技能") == "Chinese")
        #expect(TeachingReply.language(of: "How do I click 自訂?") == "English")
        #expect(TeachingReply.language(of: "スキルを作る") == "Japanese")
        #expect(TeachingReply.language(of: "A1") == nil)
        #expect(CoachClient.compose(question: "Let's try the demo", platform: "macOS", excel: nil).contains("answer in English"))
    }
}
