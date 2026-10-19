import SwiftUI

/// 4 帯の状態を横に並べる小さな表示: クリア済み ✓ / 今の帯 ● / 開いている ○ / 未到達 🔒。
/// ホームの帯カードとスコア帯クリアの画面で共用（§4.1 / §4.3.1）
struct StageChips: View {
    enum State { case locked, open, current, cleared }

    /// レベルごとの状態
    let state: (Int) -> State
    /// この帯のチェックを少し遅れて弾ませる（クリア演出用）
    var bounce: Int? = nil
    @SwiftUI.State private var bounced = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Stage.levels, id: \.self) { level in
                let s = state(level)
                VStack(spacing: 3) {
                    Image(systemName: symbol(s))
                        .font(.footnote)
                        .foregroundStyle(color(s))
                        .symbolEffect(.bounce, options: .nonRepeating, value: bounced && level == bounce)
                    Text("\(level)")
                        .font(.caption2.monospacedDigit())
                        .fontWeight(s == .current ? .bold : .regular)
                        .foregroundStyle(s == .current ? Color.primary : Color.secondary)
                        .fixedSize()
                }
            }
        }
        .accessibilityLabel(Stage.levels.map { "\($0) 点帯 \(label(state($0)))" }.joined(separator: "、"))
        .onAppear {
            guard bounce != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                bounced = true
            }
        }
    }

    private func symbol(_ s: State) -> String {
        switch s {
        case .locked: "lock.fill"
        case .cleared: "checkmark.circle.fill"
        case .current: "record.circle"
        case .open: "circle"
        }
    }

    private func color(_ s: State) -> Color {
        switch s {
        case .locked: Color.secondary.opacity(0.5)
        case .cleared: .green
        case .current, .open: Color.accentColor
        }
    }

    private func label(_ s: State) -> String {
        switch s {
        case .locked: "未到達"
        case .cleared: "クリア"
        case .current: "今ここ"
        case .open: "学習中"
        }
    }
}
