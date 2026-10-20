import Foundation

/// App Store の評価ダイアログ（`requestReview`）を出すかの判定（§4.8 [v1.8]）。純粋関数のみ。
/// 表示の可否と回数（1 年に 3 回まで）は OS が決めるので、ここでは「うまくいった直後」に絞るだけ
nonisolated enum ReviewPrompt {
    /// 正答率で頼むときに要る、累計の完走セット数
    static let minFinishedSets = 5
    /// 正答率で頼むときの下限
    static let minCorrectRatio = 0.8

    /// 頼むきっかけ。計測の値にも使う
    enum Trigger: String, Equatable, Sendable {
        case stageClear = "stage_clear"
        case highScore = "high_score"
    }

    /// セット完走時に呼ぶ。同じバージョンでは 1 回だけ
    /// - Parameters:
    ///   - finishedSets: このセットを含む累計の完走セット数
    ///   - stageCleared: このセットでスコア帯をクリアしたか
    static func trigger(correct: Int, total: Int, finishedSets: Int, stageCleared: Bool,
                        lastAskedVersion: String?, currentVersion: String) -> Trigger? {
        guard lastAskedVersion != currentVersion, total > 0 else { return nil }
        if stageCleared { return .stageClear }
        if finishedSets >= minFinishedSets, Double(correct) / Double(total) >= minCorrectRatio { return .highScore }
        return nil
    }
}
