import SwiftUI

/// 4択ボタン。Liquid Glass。回答後は正誤で色が変わる。
/// [v1.9] リスニングは回答まで文（text）を伏せ（revealed = false）、読み上げている応答をスピーカーの記号で示す（playing）
struct ChoiceButton: View {
    enum State { case idle, correct, wrong, dimmed }

    let label: String       // A〜D
    let text: String
    let state: State
    var revealed = true
    var playing = false
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
                Text(revealed ? text : "応答 \(label)")
                    .font(.body)
                    .foregroundStyle(!revealed || state == .dimmed ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !revealed {
                    Image(systemName: playing ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .font(.title3)
                        .foregroundStyle(playing ? Color.accentColor : Color.secondary)
                        .symbolEffect(.variableColor.iterative, isActive: playing)
                        .frame(width: 28)
                } else if state == .correct || state == .wrong {
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
            // 持ち上げて傾けている間はガラスを外し、平らな塗りにする（回転でガラスが膨らみ、位置もずれるのを避ける）
            .liftableGlass(glass, flat: flatFill, lifting: lifting, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .opacity(state == .dimmed ? 0.6 : 1)
        .scaleEffect(state == .correct || state == .wrong ? 1.02 : 1)
        .animation(.spring(duration: 0.35, bounce: 0.35), value: state)
        .accessibilityLabel(revealed ? "\(label). \(text)" : "応答 \(label)")
        .accessibilityValue(revealed ? accessibilityValue : (playing ? "再生中" : ""))

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
