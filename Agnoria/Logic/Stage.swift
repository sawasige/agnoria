import Foundation

/// スコア帯のステージ（§3.4 [v1.3]）。450 → 500 → 550 → 600 の順に進む。純粋関数のみ。
/// [v1.8] 進み具合は出題の種類（DrillMode）ごとの軸で別々に持つ。ここの関数は 1 つの軸の分だけを扱う
nonisolated enum Stage {
    /// この習得率でステージクリア
    static let clearRatio = 0.8
    static let levels: [Int] = Level.allCases.map(\.rawValue).sorted()
    static let first = levels[0]
    static let last = levels[levels.count - 1]

    /// 到達帯までのレベル集合（出題対象）
    static func unlockedLevels(upTo level: Int) -> Set<Int> {
        Set(levels.filter { $0 <= level })
    }

    static func next(after level: Int) -> Int? {
        levels.first { $0 > level }
    }

    static func isCleared(_ s: MasterySummary) -> Bool {
        s.total > 0 && s.masteredRatio >= clearRatio
    }

    /// クリアまであと何問習得すればよいか
    static func remainingToClear(_ s: MasterySummary) -> Int {
        max(0, Int((clearRatio * Double(s.total)).rounded(.up)) - s[.mastered])
    }

    /// 今取り組む帯: 到達帯以下で未クリアの最も低い帯。すべてクリア済みなら到達帯。
    /// [v2.0] `floor`（初回に選んだ開始の帯 §3.4）より下の帯は今の帯にしない（到達済みとして復習で混ざるだけ）
    static func current(unlocked: Int, byLevel: [Int: MasterySummary], floor: Int = first) -> Int {
        for level in levels where level >= floor && level <= unlocked {
            if !isCleared(byLevel[level] ?? MasterySummary()) { return level }
        }
        return unlocked
    }

    /// セット完走時に呼ぶ。到達帯をクリアしていれば次の帯を返す（最上位なら nil）
    static func unlock(unlocked: Int, byLevel: [Int: MasterySummary]) -> Int? {
        guard isCleared(byLevel[unlocked] ?? MasterySummary()) else { return nil }
        return next(after: unlocked)
    }

    /// セット完走でスコア帯をクリアしたときの出来事（§4.3.1 [v1.5]）。
    /// mode はクリアした軸 [v1.8]、cleared はクリアした帯、next は新しく開いた帯（最上位をクリアしたときは nil）
    struct Clear: Equatable, Hashable, Sendable {
        let mode: DrillMode
        let cleared: Int
        let next: Int?
    }

    /// セット完走時に軸ごとに呼ぶ。到達帯をクリアしていれば Clear を返す。
    /// 最上位の帯は開く先が無いので、まだ祝っていないとき（topCelebrated == false）だけ 1 回返す
    static func clearEvent(mode: DrillMode, unlocked: Int, byLevel: [Int: MasterySummary], topCelebrated: Bool) -> Clear? {
        if let next = unlock(unlocked: unlocked, byLevel: byLevel) {
            return Clear(mode: mode, cleared: unlocked, next: next)
        }
        if unlocked == last, !topCelebrated, isCleared(byLevel[last] ?? MasterySummary()) {
            return Clear(mode: mode, cleared: last, next: nil)
        }
        return nil
    }

    /// 記録から到達帯を求め直す（同期後の再計算 §2.3 [v1.7]）。最初の帯から順に、クリアしていれば次へ進む
    static func unlockedFromRecords(byLevel: [Int: MasterySummary]) -> Int {
        var unlocked = first
        while let next = next(after: unlocked), isCleared(byLevel[unlocked] ?? MasterySummary()) {
            unlocked = next
        }
        return unlocked
    }

    /// おまかせの重み係数: 今の帯 1、それ以外の到達済み帯 0.35（復習）、未到達 0
    static func weightFactor(level: Int, current: Int, unlocked: Int) -> Double {
        if level > unlocked { return 0 }
        return level == current ? 1 : 0.35
    }

    /// 1 つの軸の帯の状態（ホーム・進捗の表示用 [v1.8]）
    struct Track: Identifiable, Sendable {
        let mode: DrillMode
        let unlocked: Int
        let current: Int
        let byLevel: [Int: MasterySummary]

        var id: DrillMode { mode }
        /// 今の帯の習得状況
        var summary: MasterySummary { byLevel[current] ?? MasterySummary() }
    }

    /// 軸ごとの問題（id とレベル）と記録から、軸ごとの帯の状態を作る
    static func tracks(items: [DrillMode: [(id: String, level: Int)]], progress: [String: ProgressSnapshot],
                       unlocked: [DrillMode: Int], floor: Int = first, now: Date = .now) -> [Track] {
        DrillMode.allCases.map { mode in
            let byLevel = MasteryStats.byLevel(items: items[mode] ?? [], progress: progress, now: now)
            let u = unlocked[mode] ?? first
            return Track(mode: mode, unlocked: u, current: current(unlocked: u, byLevel: byLevel, floor: floor), byLevel: byLevel)
        }
    }

}
