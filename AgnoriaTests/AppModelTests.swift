import Foundation
import Testing
import SwiftData
@testable import Agnoria

/// 同梱の問題データをメモリに読み、in-memory の記録ストアでセットが最後まで回ることを確認する
@Suite("AppModel 通し", .serialized)
@MainActor
struct AppModelTests {
    private func makeModel() async throws -> AppModel {
        let container = try AgnoriaSchema.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)")!
        let payload = try BundleData.load(bundle: Bundle(for: ItemProgress.self))
        return AppModel(container: container, settings: AppSettings(defaults: defaults), catalog: QuestionCatalog(payload))
    }

    @Test("おまかせは単語と文法が混ざった10問になり、セッションは mode=auto で保存される") func autoRun() async throws {
        let model = try await makeModel()
        // 単語と文法は 1 つの候補群から重みで選ぶ（決め打ちの比率はない）ので、1 セットだけだと片方に偏ることがある。5 セットで見る
        var rng = SeededRandomNumberGenerator(seed: 11)
        let sets = (0..<5).map { _ in model.buildQuestions(.auto, using: &rng) }
        #expect(sets.allSatisfy { $0.count == 10 })
        let qs = sets.flatMap { $0 }
        #expect(qs.contains { $0.mode == .word })
        #expect(qs.contains { $0.mode == .grammar })

        let run = try #require(model.startQuiz(.auto))
        while !run.isFinished {
            model.answerCurrent(run.current.correctIndex)
            if !run.isLast { model.advance() }
        }
        model.finishRun()
        let sessions = try model.container.mainContext.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.first?.mode == StudySession.autoMode)
        #expect(sessions.first?.category == nil)
    }

    @Test("初回起動では今のスコアの目安を尋ね、選んだ帯で 3 軸の到達帯をそろえる。記録があれば尋ねない") func startingLevel() async throws {
        let model = try await makeModel()
        #expect(model.shouldAskStartingLevel)
        model.applyStartingLevel(.upTo600)
        #expect(!model.shouldAskStartingLevel)
        #expect(model.settings.startingLevelAsked)
        for mode in DrillMode.allCases { #expect(model.settings.unlockedLevel(mode) == 550, "\(mode)") }
        #expect(model.settings.startingLevel == 550)
        #expect(model.stageStates()[.word]?.current == 550, "開始の帯より下は今の帯にしない（復習で混ざるだけ）")
        // 下の帯は到達済みなので、おまかせでは復習の重み（0.35）で混ざる
        #expect(Stage.weightFactor(level: 450, current: 550, unlocked: 550) == 0.35)
        #expect(Stage.weightFactor(level: 550, current: 550, unlocked: 550) == 1)

        // 設定で到達帯を 450 に戻しても、1 セットでクリアにはならない（クリアは 8 割習得で決まる）
        for mode in DrillMode.allCases { model.settings.setUnlockedLevel(450, for: mode) }
        #expect(model.stageStates()[.word]?.current == 450)
        let run = try #require(model.startQuiz(QuizConfig(mode: .word, category: nil, format: nil)))
        while !run.isFinished {
            model.answerCurrent(run.current.correctIndex)
            if !run.isLast { model.advance() }
        }
        model.finishRun()
        #expect(model.pendingStageClears.isEmpty)
        #expect(model.settings.unlockedLevel(.word) == 450)
        #expect(model.path == [.result])



        // 「あとで」は 450 のまま
        let later = try await makeModel()
        later.applyStartingLevel(nil)
        #expect(later.settings.startingLevelAsked)
        #expect(later.settings.unlockedLevel(.word) == 450)

        // 記録がある端末（更新で入れた人）では尋ねず、尋ねたことにする
        let existing = try await makeModel()
        existing.progress(for: "w-0001").record(isCorrect: true)
        #expect(!existing.shouldAskStartingLevel)
        #expect(existing.settings.startingLevelAsked)
    }

    @Test("設定で到達帯を下げると、その軸のその帯以上の習得が未学習に戻る。累計・ブックマーク・他の軸は残る") func restartStage() async throws {
        let model = try await makeModel()
        let payload = try BundleData.load(bundle: Bundle(for: ItemProgress.self))
        // 単語 450 / 500 / 550 と文法 450 を 1 問ずつ習得済みにし、単語の到達帯を 550、開始の帯を 550 に
        let w450 = try #require(payload.words.first { $0.level == 450 }?.id)
        let w500 = try #require(payload.words.first { $0.level == 500 }?.id)
        let w550 = try #require(payload.words.first { $0.level == 550 }?.id)
        let g450 = try #require(payload.grammar.first { $0.level == 450 }?.id)
        for id in [w450, w500, w550, g450] {
            let p = model.progress(for: id)
            for _ in 0..<3 { p.record(isCorrect: true) }
            p.isBookmarked = true
        }
        model.settings.setUnlockedLevel(550, for: .word)
        model.settings.startingLevel = 550
        model.settings.setTopStageCelebrated(true, for: .word)

        model.restartStage(.word, from: 500)

        let w500p = model.progress(for: w500), w550p = model.progress(for: w550)
        #expect(w500p.recentResults.isEmpty && w500p.masteredAt == nil, "500 点帯以上は未学習に")
        #expect(w550p.recentResults.isEmpty && w550p.masteredAt == nil)
        #expect(w500p.totalAnswered == 3 && w500p.totalCorrect == 3 && w500p.isBookmarked, "累計とブックマークは残る")
        #expect(model.progress(for: w450).masteredAt != nil, "下の帯は残る")
        #expect(model.progress(for: g450).masteredAt != nil, "他の軸は残る")
        #expect(model.settings.unlockedLevel(.word) == 500)
        #expect(model.settings.startingLevel == 500, "開始の帯も下がる")
        #expect(!model.settings.topStageCelebrated.contains(.word))
        #expect(model.stageStates()[.word]?.current == 500)
        #expect(model.settings.stageRestartedAt[.word] != nil, "やり直しの日時を持つ（クリアまでの目安はこれ以後だけで数える）")
        #expect(model.settings.stageRestartedAt[.grammar] == nil)
    }

    @Test("おまかせにリスニングは入らず、リスニングを指定すると 3 択の応答問題だけになる") func listeningRun() async throws {


        let model = try await makeModel()
        var rng = SeededRandomNumberGenerator(seed: 5)
        for _ in 0..<5 {
            #expect(!model.buildQuestions(.auto, using: &rng).contains { $0.isListening })
            #expect(!model.buildQuestions(QuizConfig(mode: nil, category: nil, format: nil, filter: .wrongOnly), using: &rng)
                .contains { $0.isListening })
        }
        let qs = model.buildQuestions(QuizConfig(mode: .listening, category: nil, format: nil), using: &rng)
        #expect(qs.count == 10)
        #expect(qs.allSatisfy { $0.isListening && $0.choices.count == 3 && $0.choicesJa?.count == 3 })
        #expect(Set(qs.map(\.itemID)).count == 10)
        // ホームの切り替えをオンにすると、おまかせと復習にリスニングが混ざる
        model.settings.autoIncludesListening = true
        var seen = false
        for _ in 0..<10 where !seen { seen = model.buildQuestions(.auto, using: &rng).contains { $0.isListening } }
        #expect(seen)
        model.settings.autoIncludesListening = false
        // 分野を指定すると、到達帯 450 のその分野（6 問）だけ

        let wh = model.buildQuestions(QuizConfig(mode: .listening, category: "WH 疑問文", format: nil), using: &rng)
        #expect(wh.count == 6 && wh.allSatisfy { $0.categoryName == "WH 疑問文" })
        #expect(model.stageStates()[.listening]?.byLevel[450]?.total == 30)
    }

    @Test("単語・文法・リスニングそれぞれで10問セットが最後まで回り、セッションが保存される") func fullRun() async throws {
        let model = try await makeModel()
        for mode in DrillMode.allCases {
            let run = try #require(model.startQuiz(QuizConfig(mode: mode, category: nil, format: nil)))
            #expect(run.questions.count == 10)
            #expect(model.path == [.quiz])
            while !run.isFinished {
                model.answerCurrent(run.current.correctIndex)
                if !run.isLast { model.advance() }
            }
            model.finishRun()
            #expect(model.path == [.result])
            #expect(run.correctCount == 10)
        }
        let sessions = try model.container.mainContext.fetch(FetchDescriptor<StudySession>())
        #expect(sessions.count == DrillMode.allCases.count)
        #expect(sessions.allSatisfy { $0.results.count == 10 })

        let progress = try model.container.mainContext.fetch(FetchDescriptor<ItemProgress>())
        #expect(progress.count == 10 * DrillMode.allCases.count)
    }

    @Test("セット完走で、このセットで新しく習得した数を残し、次のセット開始で消す") func setGain() async throws {
        let model = try await makeModel()
        let config = QuizConfig(mode: .grammar, category: nil, format: nil)
        let run = try #require(model.startQuiz(config))
        // 半分の問題は前に 2 回正解済み → このセットの正解で習得になる
        let primed = run.questions.prefix(5).map(\.itemID)
        for id in primed {
            let p = model.progress(for: id)
            p.record(isCorrect: true, at: run.startedAt.addingTimeInterval(-86_400))
            p.record(isCorrect: true, at: run.startedAt.addingTimeInterval(-86_400))
        }
        while !run.isFinished {
            model.answerCurrent(run.current.correctIndex)
            if !run.isLast { model.advance() }
        }
        model.finishRun()
        #expect(model.lastSetGain.newlyMastered == 5)
        #expect(model.lastSetGain.nearlyMastered == 0, "残り 5 問は 1 回正解しただけ")

        _ = try #require(model.startQuiz(config))
        #expect(model.lastSetGain.newlyMastered == 0)
    }

    @Test("masteredAt 追加前に習得していた問題は起動時に補われる") func backfill() async throws {
        let model = try await makeModel()
        let ctx = model.container.mainContext
        let a = ItemProgress(itemID: "w-0001"); a.recentResults = [true, true, true]; a.lastAnsweredAt = Date(timeIntervalSince1970: 1_800_000_000)
        let b = ItemProgress(itemID: "w-0002"); b.recentResults = [true, true]; b.lastAnsweredAt = .now
        ctx.insert(a); ctx.insert(b); try ctx.save()
        model.backfillMasteredAt()
        #expect(a.masteredAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(b.masteredAt == nil)
        #expect(Mastery.of(a.snapshot) == .mastered)
    }

    @Test("分野指定・形式指定が反映される") func categoryAndFormat() async throws {
        let model = try await makeModel()
        for m in DrillMode.allCases { model.settings.setUnlockedLevel(Stage.last, for: m) }
        var rng = SeededRandomNumberGenerator(seed: 1)
        let qs = model.buildQuestions(QuizConfig(mode: .word, category: "人事・採用", format: .cloze), using: &rng)
        #expect(qs.count == 10)
        #expect(qs.allSatisfy { $0.categoryName == "人事・採用" })
        #expect(qs.allSatisfy { $0.wordFormat == .cloze })
        #expect(qs.allSatisfy { $0.prompt.contains(Cloze.blank) })
    }

    @Test("間違えた問題だけ・ブックマークだけ") func wrongAndBookmark() async throws {
        let model = try await makeModel()
        var rng = SeededRandomNumberGenerator(seed: 2)
        #expect(model.buildQuestions(QuizConfig(mode: .grammar, category: nil, format: nil, filter: .wrongOnly), using: &rng).isEmpty)

        let run = try #require(model.startQuiz(QuizConfig(mode: .grammar, category: nil, format: nil)))
        let wrongIndex = (run.current.correctIndex + 1) % 4
        model.answerCurrent(wrongIndex)
        let wrongID = run.current.itemID
        model.toggleBookmark(wrongID)
        model.abandonRun()
        #expect(model.path.isEmpty)

        let wrongOnly = model.buildQuestions(QuizConfig(mode: .grammar, category: nil, format: nil, filter: .wrongOnly), using: &rng)
        #expect(wrongOnly.map(\.itemID) == [wrongID])
        let bookmarked = model.buildQuestions(QuizConfig(mode: .grammar, category: nil, format: nil, filter: .bookmarked), using: &rng)
        #expect(bookmarked.map(\.itemID) == [wrongID])

        try model.resetHistory()
        #expect(model.buildQuestions(QuizConfig(mode: .grammar, category: nil, format: nil, filter: .bookmarked), using: &rng).isEmpty)
    }

    @Test("到達帯より上のレベルは出題されない") func stageLimitsLevels() async throws {
        let model = try await makeModel()
        let payload = try BundleData.load(bundle: Bundle(for: ItemProgress.self))
        let top = Set(payload.words.filter { $0.level == Stage.last }.map(\.id))
        try #require(!top.isEmpty)
        for m in DrillMode.allCases { model.settings.setUnlockedLevel(Stage.first, for: m) }
        #expect(model.startQuiz(QuizConfig(mode: .word, category: nil, format: nil, restrictTo: top)) == nil)
        #expect(model.path.isEmpty)
        var rng = SeededRandomNumberGenerator(seed: 5)
        let levels = Dictionary(uniqueKeysWithValues: (payload.words.map { ($0.id, $0.level) } + payload.grammar.map { ($0.id, $0.level) }))
        let auto = model.buildQuestions(.auto, using: &rng)
        #expect(!auto.isEmpty)
        #expect(auto.allSatisfy { levels[$0.itemID] == Stage.first })
        for m in DrillMode.allCases { model.settings.setUnlockedLevel(Stage.last, for: m) }
        #expect(model.startQuiz(QuizConfig(mode: .word, category: nil, format: nil, restrictTo: top)) != nil)
    }

    @Test("軸の到達帯の習得率が 80% を超えたセットの完走で、その軸だけ次の帯が開く") func unlockNextStage() async throws {
        let model = try await makeModel()
        let payload = try BundleData.load(bundle: Bundle(for: ItemProgress.self))
        let firstLevelWords = payload.words.filter { $0.level == Stage.first }.map(\.id)
        for id in firstLevelWords {
            let p = model.progress(for: id)
            for _ in 0..<3 { p.record(isCorrect: true) }
        }
        #expect(model.settings.unlockedLevel(.word) == Stage.first)
        // 文法だけのセットでは、単語の軸は判定しない
        let grammarRun = try #require(model.startQuiz(QuizConfig(mode: .grammar, category: nil, format: nil)))
        while !grammarRun.isFinished {
            model.answerCurrent(grammarRun.current.correctIndex)
            if !grammarRun.isLast { model.advance() }
        }
        model.finishRun()
        #expect(model.settings.unlockedLevel(.word) == Stage.first)
        #expect(model.pendingStageClears.isEmpty)

        let run = try #require(model.startQuiz(QuizConfig(mode: .word, category: nil, format: nil)))
        while !run.isFinished {
            model.answerCurrent(run.current.correctIndex)
            if !run.isLast { model.advance() }
        }
        model.finishRun()
        let next = Stage.next(after: Stage.first)
        #expect(model.settings.unlockedLevel(.word) == next)
        #expect(model.settings.unlockedLevel(.grammar) == Stage.first)
        #expect(model.pendingStageClears == [Stage.Clear(mode: .word, cleared: Stage.first, next: next)])
        #expect(model.lastUnlocked.map(\.mode) == [.word])
        #expect(model.path == [.stageClear])
        #expect(model.stageState(.word).current == next)
        #expect(model.stageState(.grammar).current == Stage.first)
        #expect(model.pendingReviewRequest == .stageClear)
        try model.resetHistory()
        #expect(model.settings.unlockedLevel(.word) == Stage.first)
        #expect(model.lastUnlocked.isEmpty)
    }

    @Test("1.8 への初回起動で、記録から軸ごとの到達帯を求め直し、古い合算のキーを消す") func migrateStageTracks() async throws {
        let container = try AgnoriaSchema.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "AppModelTests-\(UUID().uuidString)")!
        defaults.set(550, forKey: "unlockedLevel")   // 1.2 までの合算の到達帯
        let payload = try BundleData.load(bundle: Bundle(for: ItemProgress.self))
        let model = AppModel(container: container, settings: AppSettings(defaults: defaults), catalog: QuestionCatalog(payload))
        for id in payload.grammar.filter({ $0.level <= 500 }).map(\.id) {

            let p = model.progress(for: id)
            for _ in 0..<3 { p.record(isCorrect: true) }
        }
        #expect(!model.settings.stageTracksMigrated)
        model.prepareAtLaunch()
        #expect(model.settings.stageTracksMigrated)
        #expect(model.settings.unlockedLevel(.grammar) == 550)
        #expect(model.settings.unlockedLevel(.word) == Stage.first)
        #expect(defaults.object(forKey: "unlockedLevel") == nil)
        // 2 回目以降は求め直さない（手動で下げた帯を戻さない）
        model.settings.setUnlockedLevel(Stage.first, for: .grammar)
        model.prepareAtLaunch()
        #expect(model.settings.unlockedLevel(.grammar) == Stage.first)
    }

    @Test("全問正解を 5 セット完走すると評価ダイアログを頼み、同じバージョンでは以後頼まない") func reviewRequest() async throws {
        let model = try await makeModel()
        for n in 1...6 {
            let run = try #require(model.startQuiz(QuizConfig(mode: .word, category: nil, format: nil)))
            while !run.isFinished {
                model.answerCurrent(run.current.correctIndex)
                if !run.isLast { model.advance() }
            }
            model.finishRun()
            #expect(model.pendingReviewRequest == (n == ReviewPrompt.minFinishedSets ? .highScore : nil))
            if n == ReviewPrompt.minFinishedSets {
                #expect(model.consumeReviewRequest())
                #expect(!model.consumeReviewRequest())
                #expect(model.settings.reviewRequestedVersion == AppModel.appVersion)
            }
        }
    }
}
