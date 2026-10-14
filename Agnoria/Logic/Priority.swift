import Foundation

/// 出題優先度（§3.2）。純粋関数のみ
nonisolated enum Priority {
    static let recentWindow = 3
    /// 忘却を見込む期間。これだけ放置すると復習の重みが上限に達する
    static let forgettingDays: Double = 14

    /// 未回答: 3 / 直近に不正解あり: 2 + 不正解数 / 直近3回すべて正解: 0.3（卒業）/ それ以外: 1
    static func score(recentResults: [Bool]) -> Double {
        score(recentResults: recentResults, lastAnsweredAt: nil, now: .now)
    }

    /// 最後に答えてからの経過日数で重みを戻す（[v1.2]）。
    /// 卒業: 0.3 → 1.5（14日で上限）。その他の回答済み: 1 → 1.5。未回答と間違いは時間に依存しない
    static func score(recentResults: [Bool], lastAnsweredAt: Date?, now: Date = .now) -> Double {
        if recentResults.isEmpty { return 3 }
        let wrong = recentResults.filter { !$0 }.count
        if wrong > 0 { return 2 + Double(wrong) }
        let decay = forgetting(lastAnsweredAt: lastAnsweredAt, now: now)
        if recentResults.count >= recentWindow { return 0.3 + 1.2 * decay }
        return 1 + 0.5 * decay
    }

    /// 0（今答えた）〜 1（forgettingDays 以上放置）
    static func forgetting(lastAnsweredAt: Date?, now: Date = .now) -> Double {
        guard let lastAnsweredAt else { return 0 }
        let days = now.timeIntervalSince(lastAnsweredAt) / 86_400
        return min(max(days / forgettingDays, 0), 1)
    }

    /// スナップショットから重みを出す [v1.4]。
    /// 一度習得した問題は、直近が不正解なら間違いと同じ 2 + 不正解数、直近が正解なら卒業扱い（3連続を待たない）
    static func score(_ p: ProgressSnapshot?, now: Date = .now) -> Double {
        guard let p, !p.recentResults.isEmpty else { return 3 }
        if p.wasMastered, p.recentResults.last == true {
            return 0.3 + 1.2 * forgetting(lastAnsweredAt: p.lastAnsweredAt, now: now)
        }
        return score(recentResults: p.recentResults, lastAnsweredAt: p.lastAnsweredAt, now: now)
    }

    /// 卒業してから復習の目安（7日）を過ぎたか
    static func isDueForReview(_ p: ProgressSnapshot, now: Date = .now) -> Bool {
        isGraduated(p) && forgetting(lastAnsweredAt: p.lastAnsweredAt, now: now) >= 0.5
    }

    static func isGraduated(_ recentResults: [Bool]) -> Bool {
        recentResults.count >= recentWindow && recentResults.allSatisfy { $0 }
    }

    /// 習得の判定 [v1.4]: 直近3回すべて正解、または 過去に習得済みで直近が正解
    static func isGraduated(_ p: ProgressSnapshot) -> Bool {
        isGraduated(p.recentResults) || (p.wasMastered && p.recentResults.last == true)
    }

    static func hasRecentMistake(_ recentResults: [Bool]) -> Bool {
        recentResults.contains(false)
    }
}

/// 重み付きランダム抽出（重複なし）
nonisolated enum WeightedSampler {
    static func sample<T>(_ items: [(item: T, weight: Double)], count: Int,
                          using rng: inout some RandomNumberGenerator) -> [T] {
        var pool = items.filter { $0.weight > 0 }
        var picked: [T] = []
        while picked.count < count, !pool.isEmpty {
            let total = pool.reduce(0) { $0 + $1.weight }
            var r = Double.random(in: 0..<total, using: &rng)
            var index = pool.count - 1
            for (i, entry) in pool.enumerated() {
                r -= entry.weight
                if r < 0 { index = i; break }
            }
            picked.append(pool.remove(at: index).item)
        }
        return picked
    }
}

/// 選択肢のシャッフル。正解インデックスを追跡する
nonisolated enum ChoiceShuffler {
    static func shuffle(_ choices: [String], correctIndex: Int,
                        using rng: inout some RandomNumberGenerator) -> (choices: [String], correctIndex: Int) {
        let order = Array(choices.indices).shuffled(using: &rng)
        let shuffled = order.map { choices[$0] }
        let newIndex = order.firstIndex(of: correctIndex) ?? 0
        return (shuffled, newIndex)
    }
}

/// テスト用の決定的 RNG（SplitMix64）
nonisolated struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
