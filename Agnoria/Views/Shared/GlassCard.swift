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
            .background(Color.primary.opacity(lifting ? 0.06 : 0), in: .rect(cornerRadius: cornerRadius))
            .glassEffect(lifting ? .identity : .regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
