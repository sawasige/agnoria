import Testing
@testable import Agnoria

@Suite("ステージ")
struct StageTests {
    private func summary(mastered: Int, total: Int) -> MasterySummary {
        var s = MasterySummary()
        s.counts[.mastered] = mastered
        s.counts[.unseen] = total - mastered
        return s
    }

    @Test("到達帯までが出題対象") func unlocked() {
        #expect(Stage.unlockedLevels(upTo: 450) == [450])
        #expect(Stage.unlockedLevels(upTo: 550) == [450, 500, 550])
        #expect(Stage.next(after: 450) == 500)
        #expect(Stage.next(after: 600) == nil)
    }

    @Test("セット完走時のクリア判定: 次の帯が開く / 最上位は 1 回だけ") func clearEvent() {
        let cleared = summary(mastered: 90, total: 100)
        let notYet = summary(mastered: 50, total: 100)
        #expect(Stage.clearEvent(unlocked: 450, byLevel: [450: cleared], topCelebrated: false)
                == Stage.Clear(cleared: 450, next: 500))
        #expect(Stage.clearEvent(unlocked: 450, byLevel: [450: notYet], topCelebrated: false) == nil)
        #expect(Stage.clearEvent(unlocked: 600, byLevel: [600: cleared], topCelebrated: false)
                == Stage.Clear(cleared: 600, next: nil))
        #expect(Stage.clearEvent(unlocked: 600, byLevel: [600: cleared], topCelebrated: true) == nil)
        #expect(Stage.clearEvent(unlocked: 600, byLevel: [600: notYet], topCelebrated: false) == nil)
    }

    @Test("クリア判定とあと何問") func clear() {
        #expect(!Stage.isCleared(MasterySummary()))
        #expect(!Stage.isCleared(summary(mastered: 79, total: 100)))
        #expect(Stage.isCleared(summary(mastered: 80, total: 100)))
        #expect(Stage.remainingToClear(summary(mastered: 50, total: 100)) == 30)
        #expect(Stage.remainingToClear(summary(mastered: 20, total: 25)) == 0)
        #expect(Stage.remainingToClear(summary(mastered: 0, total: 25)) == 20)
    }

    @Test("今の帯は到達帯以下で未クリアの最も低い帯") func current() {
        let cleared = summary(mastered: 90, total: 100)
        let open = summary(mastered: 10, total: 100)
        #expect(Stage.current(unlocked: 450, byLevel: [450: open]) == 450)
        #expect(Stage.current(unlocked: 550, byLevel: [450: cleared, 500: open, 550: open]) == 500)
        #expect(Stage.current(unlocked: 550, byLevel: [450: cleared, 500: cleared, 550: cleared]) == 550)
        #expect(Stage.current(unlocked: 500, byLevel: [:]) == 450)
    }

    @Test("クリアしたら次の帯が開く。最上位なら nil") func unlock() {
        let cleared = summary(mastered: 90, total: 100)
        let open = summary(mastered: 10, total: 100)
        #expect(Stage.unlock(unlocked: 450, byLevel: [450: cleared]) == 500)
        #expect(Stage.unlock(unlocked: 450, byLevel: [450: open]) == nil)
        #expect(Stage.unlock(unlocked: 600, byLevel: [600: cleared]) == nil)
    }

    @Test("重み係数: 今の帯 1、到達済み 0.35、未到達 0") func factor() {
        #expect(Stage.weightFactor(level: 500, current: 500, unlocked: 550) == 1)
        #expect(Stage.weightFactor(level: 450, current: 500, unlocked: 550) == 0.35)
        #expect(Stage.weightFactor(level: 550, current: 500, unlocked: 550) == 0.35)
        #expect(Stage.weightFactor(level: 600, current: 500, unlocked: 550) == 0)
    }
}
