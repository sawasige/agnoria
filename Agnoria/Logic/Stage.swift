import Foundation

/// スコア帯のステージ（§3.4 [v1.3]）。450 → 500 → 550 → 600 の順に進む。純粋関数のみ
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

    /// 今取り組む帯: 到達帯以下で未クリアの最も低い帯。すべてクリア済みなら到達帯
    static func current(unlocked: Int, byLevel: [Int: MasterySummary]) -> Int {
        for level in levels where level <= unlocked {
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
    /// cleared はクリアした帯、next は新しく開いた帯（最上位をクリアしたときは nil）
    struct Clear: Equatable, Hashable, Sendable {
        let cleared: Int
        let next: Int?
    }

    /// セット完走時に呼ぶ。到達帯をクリアしていれば Clear を返す。
    /// 最上位の帯は開く先が無いので、まだ祝っていないとき（topCelebrated == false）だけ 1 回返す
    static func clearEvent(unlocked: Int, byLevel: [Int: MasterySummary], topCelebrated: Bool) -> Clear? {
        if let next = unlock(unlocked: unlocked, byLevel: byLevel) {
            return Clear(cleared: unlocked, next: next)
        }
        if unlocked == last, !topCelebrated, isCleared(byLevel[last] ?? MasterySummary()) {
            return Clear(cleared: last, next: nil)
        }
        return nil
    }

    /// おまかせの重み係数: 今の帯 1、それ以外の到達済み帯 0.35（復習）、未到達 0
    static func weightFactor(level: Int, current: Int, unlocked: Int) -> Double {
        if level > unlocked { return 0 }
        return level == current ? 1 : 0.35
    }
}
