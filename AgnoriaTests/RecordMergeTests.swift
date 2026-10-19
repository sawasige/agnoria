import Foundation
import SwiftData
import Testing
@testable import Agnoria

@Suite("iCloud 同期の衝突規則")
struct RecordMergeTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("回答数が多い方を正、ブックマークは OR、直近の結果は新しい方、習得日は早い方") func merge() {
        var a = ProgressSnapshot(itemID: "w-1")
        a.totalAnswered = 5; a.totalCorrect = 4; a.recentResults = [true, true, true]
        a.lastAnsweredAt = t0; a.masteredAt = t0; a.isBookmarked = false
        var b = ProgressSnapshot(itemID: "w-1")
        b.totalAnswered = 2; b.totalCorrect = 1; b.recentResults = [false, true]
        b.lastAnsweredAt = t0.addingTimeInterval(3600); b.masteredAt = nil; b.isBookmarked = true

        let m = RecordMerge.merge(a, b)
        #expect(m.totalAnswered == 5 && m.totalCorrect == 4)
        #expect(m.isBookmarked == true)
        #expect(m.recentResults == [false, true])          // 新しい方
        #expect(m.lastAnsweredAt == t0.addingTimeInterval(3600))
        #expect(m.masteredAt == t0)
        #expect(RecordMerge.merge(b, a) == m)               // 順序に依らない
    }

    @Test("同数なら最後に答えた方を正にする") func tie() {
        var a = ProgressSnapshot(itemID: "w-2"); a.totalAnswered = 3; a.totalCorrect = 3; a.lastAnsweredAt = t0
        var b = ProgressSnapshot(itemID: "w-2"); b.totalAnswered = 3; b.totalCorrect = 1; b.lastAnsweredAt = t0.addingTimeInterval(10)
        #expect(RecordMerge.merge(a, b).totalCorrect == 1)
        #expect(RecordMerge.merge([a, b, a])?.totalCorrect == 1)
    }

    @Test("記録から到達帯を求め直す") func unlockedFromRecords() {
        func s(_ mastered: Int, _ total: Int) -> MasterySummary {
            var m = MasterySummary(); m.counts[.mastered] = mastered; m.counts[.unseen] = total - mastered; return m
        }
        #expect(Stage.unlockedFromRecords(byLevel: [:]) == 450)
        #expect(Stage.unlockedFromRecords(byLevel: [450: s(8, 10)]) == 500)
        #expect(Stage.unlockedFromRecords(byLevel: [450: s(8, 10), 500: s(9, 10), 550: s(1, 10)]) == 550)
        #expect(Stage.unlockedFromRecords(byLevel: [450: s(8, 10), 500: s(8, 10), 550: s(8, 10), 600: s(10, 10)]) == 600)
        #expect(Stage.unlockedFromRecords(byLevel: [500: s(8, 10)]) == 450)   // 450 を飛ばしては進まない
    }

    @Test("同じ itemID / id の重複を 1 件にまとめる") @MainActor func dedupe() throws {
        let container = try AgnoriaSchema.makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "RecordMergeTests-\(UUID().uuidString)")!
        let model = AppModel(container: container, settings: AppSettings(defaults: defaults))
        let ctx = container.mainContext
        let p1 = ItemProgress(itemID: "w-9"); p1.totalAnswered = 4; p1.totalCorrect = 2; p1.lastAnsweredAt = t0
        let p2 = ItemProgress(itemID: "w-9"); p2.totalAnswered = 1; p2.totalCorrect = 1; p2.isBookmarked = true; p2.lastAnsweredAt = t0.addingTimeInterval(5)
        ctx.insert(p1); ctx.insert(p2)
        let s1 = StudySession(startedAt: t0, finishedAt: t0, mode: nil, category: nil, questionFormat: nil, results: [])
        let s2 = StudySession(startedAt: t0, finishedAt: t0, mode: nil, category: nil, questionFormat: nil, results: [])
        s2.id = s1.id
        ctx.insert(s1); ctx.insert(s2)
        try ctx.save()

        model.mergeDuplicateRecords()
        let progress = try ctx.fetch(FetchDescriptor<ItemProgress>())
        #expect(progress.count == 1)
        #expect(progress[0].totalAnswered == 4 && progress[0].isBookmarked == true)
        #expect(try ctx.fetch(FetchDescriptor<StudySession>()).count == 1)
        #expect(model.progress(for: "w-9").totalAnswered == 4)
    }
}
