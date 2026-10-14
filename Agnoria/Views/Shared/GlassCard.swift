import SwiftUI

extension EnvironmentValues {
    /// クイズのカードを指で持ち上げて傾けている間 true（§4.2 [v1.4]）。
    /// Liquid Glass は回転すると回転前の外接矩形に膨らんで描かれるので、この間だけガラスを平らな塗りに置き換える
    @Entry var cardLifting: Bool = false
}

/// コンテンツを載せる Liquid Glass のカード。背景の AppBackground を屈折させる
struct GlassCardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat
    @Environment(\.cardLifting) private var lifting

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .liftableGlass(.regular, flat: Color.primary.opacity(0.06), lifting: lifting, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Liquid Glass を付ける。ただしカードを持ち上げて傾けている間（lifting）はガラスの修飾子そのものを外して平らな塗りにする。
    /// `.glassEffect(.identity)` に切り替えるだけでは足りない: ガラスの要素は回転した親の中で描画位置が文字と合わず、
    /// 縦に 10pt ほどずれて見える（実機で確認、SPEC-REVIEW I13）
    @ViewBuilder
    func liftableGlass(_ glass: Glass, flat: Color, lifting: Bool, in shape: some Shape) -> some View {
        if lifting {
            background(flat, in: shape)
        } else {
            glassEffect(glass, in: shape)
        }
    }
}

extension View {
    func glassCard(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
