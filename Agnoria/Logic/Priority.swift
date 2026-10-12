import Foundation

/// 出題優先度（§3.2）。純粋関数のみ
enum Priority {
    static let recentWindow = 3

    /// 未回答: 3 / 直近に不正解あり: 2 + 不正解数 / 直近3回すべて正解: 0.3（卒業）/ それ以外: 1
    static func score(recentResults: [Bool]) -> Double {
        if recentResults.isEmpty { return 3 }
        let wrong = recentResults.filter { !$0 }.count
        if wrong > 0 { return 2 + Double(wrong) }
        if recentResults.count >= recentWindow { return 0.3 }
        return 1
    }

    static func isGraduated(_ recentResults: [Bool]) -> Bool {
        recentResults.count >= recentWindow && recentResults.allSatisfy { $0 }
    }

    static func hasRecentMistake(_ recentResults: [Bool]) -> Bool {
        recentResults.contains(false)
    }
}

/// 重み付きランダム抽出（重複なし）
enum WeightedSampler {
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
enum ChoiceShuffler {
    static func shuffle(_ choices: [String], correctIndex: Int,
                        using rng: inout some RandomNumberGenerator) -> (choices: [String], correctIndex: Int) {
        let order = Array(choices.indices).shuffled(using: &rng)
        let shuffled = order.map { choices[$0] }
        let newIndex = order.firstIndex(of: correctIndex) ?? 0
        return (shuffled, newIndex)
    }
}

/// テスト用の決定的 RNG（SplitMix64）
struct SeededRandomNumberGenerator: RandomNumberGenerator {
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
