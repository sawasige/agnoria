import Testing
@testable import Agnoria

@Suite("評価ダイアログの判定")
struct ReviewPromptTests {
    @Test("帯のクリアなら完走セット数に関係なく頼む") func stageClear() {
        #expect(ReviewPrompt.trigger(correct: 5, total: 10, finishedSets: 1, stageCleared: true,
                                     lastAskedVersion: nil, currentVersion: "1.3") == .stageClear)
    }

    @Test("正答率 8 割以上で、累計 5 セット以上のときだけ頼む") func highScore() {
        #expect(ReviewPrompt.trigger(correct: 8, total: 10, finishedSets: 5, stageCleared: false,
                                     lastAskedVersion: nil, currentVersion: "1.3") == .highScore)
        #expect(ReviewPrompt.trigger(correct: 10, total: 10, finishedSets: 4, stageCleared: false,
                                     lastAskedVersion: nil, currentVersion: "1.3") == nil)
        #expect(ReviewPrompt.trigger(correct: 7, total: 10, finishedSets: 20, stageCleared: false,
                                     lastAskedVersion: nil, currentVersion: "1.3") == nil)
        #expect(ReviewPrompt.trigger(correct: 0, total: 0, finishedSets: 20, stageCleared: true,
                                     lastAskedVersion: nil, currentVersion: "1.3") == nil)
    }

    @Test("同じバージョンでは 2 回頼まない。バージョンが変われば再び頼む") func oncePerVersion() {
        #expect(ReviewPrompt.trigger(correct: 10, total: 10, finishedSets: 9, stageCleared: true,
                                     lastAskedVersion: "1.3", currentVersion: "1.3") == nil)
        #expect(ReviewPrompt.trigger(correct: 10, total: 10, finishedSets: 9, stageCleared: false,
                                     lastAskedVersion: "1.2", currentVersion: "1.3") == .highScore)
    }
}
