import Foundation

/// 回答後の「左スワイプで次へ」の判定（§4.2 [v1.4]）。純粋関数のみ
nonisolated enum SwipeNext {
    /// 指を離した時点の移動量がこれ以上なら成立
    static let distance: CGFloat = 60
    /// 速いフリック: 予測到達点がこれ以上なら距離が短くても成立
    static let flick: CGFloat = 140

    /// 横の動きが縦より大きく、左向きで、距離かフリックのどちらかを満たすとき true
    static func triggers(translation: CGSize, predicted: CGSize) -> Bool {
        guard abs(translation.width) > abs(translation.height) else { return false }
        guard translation.width < 0 else { return false }
        return translation.width <= -distance || predicted.width <= -flick
    }
}
