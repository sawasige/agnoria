import Foundation

/// iCloud 同期で同じ itemID の ItemProgress が 2 件になったときの合成規則（§2.3 [v1.7]）。純粋関数
nonisolated enum RecordMerge {
    /// totalAnswered が多い方を正とし、isBookmarked は OR、recentResults と lastAnsweredAt は新しい方、
    /// masteredAt は早い方。同数なら lastAnsweredAt が新しい方を正
    static func merge(_ a: ProgressSnapshot, _ b: ProgressSnapshot) -> ProgressSnapshot {
        let base: ProgressSnapshot
        let other: ProgressSnapshot
        if a.totalAnswered != b.totalAnswered {
            (base, other) = a.totalAnswered > b.totalAnswered ? (a, b) : (b, a)
        } else {
            (base, other) = (a.lastAnsweredAt ?? .distantPast) >= (b.lastAnsweredAt ?? .distantPast) ? (a, b) : (b, a)
        }
        let newer = (base.lastAnsweredAt ?? .distantPast) >= (other.lastAnsweredAt ?? .distantPast) ? base : other
        var m = base
        m.isBookmarked = base.isBookmarked || other.isBookmarked
        m.recentResults = newer.recentResults
        m.lastAnsweredAt = newer.lastAnsweredAt
        m.masteredAt = [base.masteredAt, other.masteredAt].compactMap { $0 }.min()
        return m
    }

    /// 同じ itemID の複数件を 1 件にまとめる
    static func merge(_ all: [ProgressSnapshot]) -> ProgressSnapshot? {
        guard var acc = all.first else { return nil }
        for s in all.dropFirst() { acc = merge(acc, s) }
        return acc
    }
}
