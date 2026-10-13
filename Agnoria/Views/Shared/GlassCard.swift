import SwiftUI

/// コンテンツを載せる Liquid Glass のカード。背景の AppBackground を屈折させる
struct GlassCardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
