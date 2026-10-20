import Foundation
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

    @Test("卒業した問題は時間が経つと重みが戻る（14日で上限 1.5）") func forgettingRaisesGraduated() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        let g = [true, true, true]
        #expect(Priority.score(recentResults: g, lastAnsweredAt: now, now: now) == 0.3)
        let week = Priority.score(recentResults: g, lastAnsweredAt: now.addingTimeInterval(-7 * day), now: now)
        #expect(abs(week - 0.9) < 0.0001)
        let twoWeeks = Priority.score(recentResults: g, lastAnsweredAt: now.addingTimeInterval(-14 * day), now: now)
        #expect(abs(twoWeeks - 1.5) < 0.0001)
        let month = Priority.score(recentResults: g, lastAnsweredAt: now.addingTimeInterval(-30 * day), now: now)
        #expect(abs(month - 1.5) < 0.0001)
        // 学習中も少し戻る。未回答・間違いは時間に依存しない
        let learning = Priority.score(recentResults: [true], lastAnsweredAt: now.addingTimeInterval(-30 * day), now: now)
        #expect(abs(learning - 1.5) < 0.0001)
        #expect(Priority.score(recentResults: [false], lastAnsweredAt: now.addingTimeInterval(-30 * day), now: now) == 3)
        #expect(Priority.score(recentResults: [], lastAnsweredAt: nil, now: now) == 3)
    }

    @Test("復習のころあい: 卒業後7日以上") func dueForReview() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = ProgressSnapshot(itemID: "a", recentResults: [true, true, true], lastAnsweredAt: now)
        let old = ProgressSnapshot(itemID: "b", recentResults: [true, true, true],
                                   lastAnsweredAt: now.addingTimeInterval(-8 * 86_400))
        let oldWrong = ProgressSnapshot(itemID: "c", recentResults: [true, false, true],
                                        lastAnsweredAt: now.addingTimeInterval(-8 * 86_400))
        #expect(!Priority.isDueForReview(fresh, now: now))
        #expect(Priority.isDueForReview(old, now: now))
        #expect(!Priority.isDueForReview(oldWrong, now: now))
    }
}

@Suite("セット生成")
struct SetBuilderTests {
    private func candidate(_ id: String, _ results: [Bool]?, category: String = "品詞", level: Int = 500,
                           bookmarked: Bool = false, mode: DrillMode = .grammar) -> SetBuilder.Candidate {
        SetBuilder.Candidate(id: id, mode: mode, category: category, level: level,
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

    @Test("おまかせ（mode nil）は単語と文法の両方から選ぶ。mode 指定なら片方だけ") func autoMixesModes() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let all = (0..<20).map { candidate("g\($0)", nil, mode: .grammar) }
            + (0..<20).map { candidate("w\($0)", nil, category: "ビジネス一般", mode: .word) }
        let auto = SetBuilder.eligible(all, config: .auto, enabledLevels: SetBuilder.allLevels)
        #expect(auto.count == 40)
        let picked = SetBuilder.pick(from: auto, using: &rng)
        #expect(picked.count == 10)
        #expect(picked.contains { $0.mode == .grammar })
        #expect(picked.contains { $0.mode == .word })

        let wordsOnly = SetBuilder.eligible(all, config: QuizConfig(mode: .word, category: nil, format: nil),
                                            enabledLevels: SetBuilder.allLevels)
        #expect(wordsOnly.count == 20)
        #expect(wordsOnly.allSatisfy { $0.mode == .word })
        #expect(QuizConfig.auto.categoryTitle == "おまかせ")
    }

    @Test("フィルタ: 分野・レベル・間違いのみ・ブックマーク") func filters() {
        let all = [
            candidate("a", nil, category: "品詞", level: 450),
            candidate("b", [false], category: "語彙", level: 600),
            candidate("c", [true, true, true], category: "品詞", level: 500, bookmarked: true),
        ]
        let cat = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: "品詞", format: nil),
                                      enabledLevels: SetBuilder.allLevels)
        #expect(cat.map(\.id) == ["a", "c"])

        let lvl = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: nil, format: nil),
                                      enabledLevels: [.grammar: [600], .word: Level.allValues])
        #expect(lvl.map(\.id) == ["b"])

        let wrong = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: nil, format: nil, filter: .wrongOnly),
                                        enabledLevels: SetBuilder.allLevels)
        #expect(wrong.map(\.id) == ["b"])

        let bm = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: nil, format: nil, filter: .bookmarked),
                                     enabledLevels: SetBuilder.allLevels)
        #expect(bm.map(\.id) == ["c"])

        let restricted = SetBuilder.eligible(all, config: QuizConfig(mode: .grammar, category: nil, format: nil, restrictTo: ["a", "b"]),
                                             enabledLevels: SetBuilder.allLevels)
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

    @Test("はじめて3連続正解した日時を masteredAt に残し、その後は変えない") func masteredAt() {
        let p = ItemProgress(itemID: "x")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        p.record(isCorrect: true, at: t0)
        p.record(isCorrect: true, at: t0.addingTimeInterval(60))
        #expect(p.masteredAt == nil)
        p.record(isCorrect: true, at: t0.addingTimeInterval(120))
        #expect(p.masteredAt == t0.addingTimeInterval(120))
        p.record(isCorrect: false, at: t0.addingTimeInterval(180))
        p.record(isCorrect: true, at: t0.addingTimeInterval(240))
        p.record(isCorrect: true, at: t0.addingTimeInterval(300))
        p.record(isCorrect: true, at: t0.addingTimeInterval(360))
        #expect(p.masteredAt == t0.addingTimeInterval(120))
        #expect(p.snapshot.wasMastered)
    }
}

@Suite("習得済みの復習 [v1.4]")
struct RelearnTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snap(_ results: [Bool], mastered: Bool) -> ProgressSnapshot {
        ProgressSnapshot(itemID: "x", recentResults: results, totalCorrect: 0, totalAnswered: results.count,
                         lastAnsweredAt: now, masteredAt: mastered ? now.addingTimeInterval(-86_400) : nil)
    }

    @Test("一度習得した問題は、間違えても次の正解で習得に戻る") func backToMastered() {
        #expect(!Priority.isGraduated(snap([true, true, false], mastered: true)))
        #expect(Priority.isGraduated(snap([true, false, true], mastered: true)))
        #expect(!Priority.isGraduated(snap([true, false, true], mastered: false)))
        #expect(Mastery.of(snap([true, false, true], mastered: true)) == .mastered)
        #expect(Mastery.of(snap([true, true, false], mastered: true)) == .learning)
        #expect(Mastery.of(snap([true, true, false], mastered: false)) == .struggling)
    }

    @Test("重み: 習得済みで直近が不正解なら間違いと同じ、直近が正解なら卒業扱い") func weights() {
        #expect(Priority.score(snap([true, true, false], mastered: true), now: now) == 3)
        #expect(Priority.score(snap([true, false, true], mastered: true), now: now) == 0.3)
        #expect(Priority.score(snap([true, false, true], mastered: false), now: now) == 3)
        #expect(Priority.score(snap([true, true, true], mastered: false), now: now) == 0.3)
        #expect(Priority.score(nil, now: now) == 3)
        #expect(Priority.score(snap([], mastered: false), now: now) == 3)
    }

    @Test("間違えた問題フィルタには、習得済みでも直近で間違えたものが含まれる") func wrongFilter() {
        let p = snap([true, true, false], mastered: true)
        #expect(MasteryStats.wrongCount(itemIDs: ["x"], progress: ["x": p]) == 1)
    }
}
