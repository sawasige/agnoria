import SwiftUI

/// 4択ボタン。Liquid Glass。回答後は正誤で色が変わる
struct ChoiceButton: View {
    enum State { case idle, correct, wrong, dimmed }

    let label: String       // A〜D
    let text: String
    let state: State
    let action: () -> Void
    @Environment(\.cardLifting) private var lifting

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Text(label)
                    .font(.subheadline.weight(.bold))
                    .fontDesign(.rounded)
                    .frame(width: 28, height: 28)
                    .background(badgeBackground, in: Circle())
                    .foregroundStyle(badgeForeground)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.body)
                    .foregroundStyle(state == .dimmed ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if state == .correct || state == .wrong {
                    Image(systemName: state == .correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(state == .correct ? .green : .red)
                        .symbolEffect(.bounce, options: .nonRepeating, value: state)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            // 持ち上げて傾けている間はガラスを切り、平らな塗りにする（回転でガラスが膨らむのを避ける）
            .background(flatFill.opacity(lifting ? 1 : 0), in: .rect(cornerRadius: 16))
            .glassEffect(lifting ? .identity : glass, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .opacity(state == .dimmed ? 0.6 : 1)
        .scaleEffect(state == .correct || state == .wrong ? 1.02 : 1)
        .animation(.spring(duration: 0.35, bounce: 0.35), value: state)
        .accessibilityLabel("\(label). \(text)")
        .accessibilityValue(accessibilityValue)
    }

    private var glass: Glass {
        switch state {
        case .idle: .regular.interactive()
        case .correct: .regular.tint(.green.opacity(0.45))
        case .wrong: .regular.tint(.red.opacity(0.45))
        case .dimmed: .regular
        }
    }

    private var flatFill: Color {
        switch state {
        case .correct: .green.opacity(0.35)
        case .wrong: .red.opacity(0.35)
        default: Color.primary.opacity(0.07)
        }
    }

    private var badgeBackground: Color {
        switch state {
        case .correct: .green
        case .wrong: .red
        default: Color.secondary.opacity(0.15)
        }
    }

    private var badgeForeground: Color {
        switch state {
        case .correct, .wrong: .white
        default: .secondary
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .correct: "正解"
        case .wrong: "不正解"
        default: ""
        }
    }
}
