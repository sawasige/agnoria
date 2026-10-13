import SwiftUI

/// 女神 Agenoria の表情（§4.3 [v1.4]）。結果に応じて切り替える演出で、ロジックには関わらない
nonisolated enum AgenoriaExpression: CaseIterable, Sendable {
    case joy, happy, neutral, sad

    var imageName: String {
        switch self {
        case .joy: "AgenoriaJoy"
        case .happy: "AgenoriaHappy"
        case .neutral: "AgenoriaNeutral"
        case .sad: "AgenoriaSad"
        }
    }

    /// 結果画面のメッセージと同じ閾値: 全問正解 / 80% 以上 / 50% 以上 / それ未満
    static func forScore(correct: Int, total: Int) -> AgenoriaExpression {
        guard total > 0 else { return .neutral }
        let ratio = Double(correct) / Double(total)
        switch ratio {
        case 1: return .joy
        case 0.8...: return .happy
        case 0.5...: return .neutral
        default: return .sad
        }
    }
}

/// 表情つきの立ち絵。表示時にふわっと現れる。装飾なので VoiceOver からは隠す
struct AgenoriaFace: View {
    let expression: AgenoriaExpression
    var height: CGFloat = 160
    @State private var shown = false

    var body: some View {
        Image(expression.imageName)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .scaleEffect(shown ? 1 : 0.9)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.6, bounce: 0.25).delay(0.05)) { shown = true }
            }
            .accessibilityHidden(true)
    }
}
