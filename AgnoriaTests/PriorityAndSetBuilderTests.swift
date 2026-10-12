import Testing
@testable import Agnoria

@Suite("優先度スコア")
struct PriorityTests {
    @Test func unanswered() { #expect(Priority.score(recentResults: []) == 3) }
    @Test func oneWrong() { #expect(Priority.score(recentResults: [true, false, true]) == 3) }
    @Test func threeWrong() { #expect(Priority.score(recentResults: [false, false, false]) == 5) }
    @Test func graduated() { #expect(Priority.score(recentResults: [true, true, true]) == 0.3) }
    @Test func partiallyCorrect() { #expect(Priority.score(recentResults: [true, true]) == 1) }
    @Test func graduationFlags() {
        #expect(Priority.isGraduated([true, true, true]))
        #expect(!Priority.isGraduated([true, true]))
        #expect(Priority.hasRecentMistake([true, false, true]))
        #expect(!Priority.hasRecentMistake([]))
    }
}

@Suite("セット生成")
struct SetBuilderTests {
    private func candidate(_ id: String, _ results: [Bool]?, category: String = "品詞", level: Int = 500,
                           bookmarked: Bool = false) -> SetBuilder.Candidate {
        SetBuilder.Candidate(id: id, category: category, level: level,
                             progress: results.map {
                                 ProgressSnapshot(itemID: id, recentResults: $0, isBookmarked: bookmarked)
                             })
    }

    @Test("対象が10件未満ならあるだけ出す") func fewerThanTen() {
        var rng = SeededRandomNumberGenerator(seed: 1)
        let picked = SetBuilder.pick(from: (0..<4).map { candidate("g\($0)", nil) }, using: &rng)
        #expect(picked.count == 4)
        #expect(Set(picked.map(\.id)).count == 4)
    }

    @Test("10件に収まり重複しない") func capAtTen() {
        var rng = SeededRandomNumberGenerator(seed: 2)
        let picked = SetBuilder.pick(from: (0..<50).map { candidate("g\($0)", nil) }, using: &rng)
        #expect(picked.count == 10)
        #expect(Set(picked.map(\.id)).count == 10)
    }

    @Test("間違えた問題が優先的に再出題される") func wrongItemsPreferred() {
        // 20件: 10件は直近に不正解あり（score 3）、10件は1回正解のみ（score 1）
        let wrong = (0..<10).map { candidate("w\($0)", [false]) }
        let ok = (0..<10).map { candidate("o\($0)", [true]) }
        var rng = SeededRandomNumberGenerator(seed: 3)
        var wrongHits = 0, okHits = 0
        for _ in 0..<500 {
            let picked = SetBuilder.pick(from: wrong + ok, count: 5, using: &rng)
            wrongHits += picked.filter { $0.id.hasPrefix("w") }.count
            okHits += picked.filter { $0.id.hasPrefix("o") }.count
        }
        // 重み比 3:1 なので、少なくとも2倍以上は差がつくはず
        #expect(wrongHits > okHits * 2)
    }

    @Test("3回連続正解した問題の出題頻度が下がる") func graduatedItemsRare() {
        let graduated = (0..<10).map { candidate("g\($0)", [true, true, true]) }
        let fresh = (0..<10).map { candidate("f\($0)", nil) }
        var rng = SeededRandomNumberGenerator(seed: 4)
        var gHits = 0, fHits = 0
        for _ in 0..<500 {
            let picked = SetBuilder.pick(from: graduated + fresh, count: 5, using: &rng)
            gHits += picked.filter { $0.id.hasPrefix("g") }.count
            fHits += picked.filter { $0.id.hasPrefix("f") }.count
        }
        // 重み比 0.3:3 = 1:10
        #expect(fHits > gHits * 4)
        #expect(gHits > 0, "卒業しても除外はしない")
    }

    @Test("フィルタ: 分野・レベル・間違いのみ・ブックマーク") func filters() {
        let all = [
            candidate("a", nil, category: "品詞", level: 450),
            candidate("b", [false], category: "語彙", level: 600),
            candidate("c", [true, true, true], category: "品詞", level: 500, bookmarked: true),
        ]
        let cat = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: "品詞", format: nil),
                                      enabledLevels: Level.allValues)
        #expect(cat.map(\.id) == ["a", "c"])

        let lvl = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: nil, format: nil),
                                      enabledLevels: [600])
        #expect(lvl.map(\.id) == ["b"])

        let wrong = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: nil, format: nil, filter: .wrongOnly),
                                        enabledLevels: Level.allValues)
        #expect(wrong.map(\.id) == ["b"])

        let bm = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: nil, format: nil, filter: .bookmarked),
                                     enabledLevels: Level.allValues)
        #expect(bm.map(\.id) == ["c"])

        let restricted = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: nil, format: nil, restrictTo: ["a", "b"]),
                                             enabledLevels: Level.allValues)
        #expect(restricted.map(\.id) == ["a", "b"])
    }

    @Test("選択肢シャッフル後も正解インデックスが追従する") func shuffleTracksAnswer() {
        var rng = SeededRandomNumberGenerator(seed: 5)
        for _ in 0..<50 {
            let (choices, idx) = ChoiceShuffler.shuffle(["a", "b", "c", "d"], correctIndex: 2, using: &rng)
            #expect(choices[idx] == "c")
            #expect(Set(choices) == ["a", "b", "c", "d"])
        }
    }
}

@Suite("Progress 記録")
struct ProgressRecordTests {
    @Test("直近3回だけ保持する") func recentWindow() {
        let p = ItemProgress(itemID: "x")
        p.record(isCorrect: false)
        p.record(isCorrect: true)
        p.record(isCorrect: true)
        p.record(isCorrect: true)
        #expect(p.recentResults == [true, true, true])
        #expect(p.totalAnswered == 4)
        #expect(p.totalCorrect == 3)
    }
}
