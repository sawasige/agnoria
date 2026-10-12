import SwiftUI

/// 4択ボタン。回答後は正誤で色が変わる
struct ChoiceButton: View {
    enum State { case idle, correct, wrong, dimmed }

    let label: String       // A〜D
    let text: String
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(.headline.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                marker
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(state == .dimmed ? .secondary : .primary)
        .accessibilityLabel("\(label). \(text)")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder private var marker: some View {
        switch state {
        case .correct: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .wrong: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        default: EmptyView()
        }
    }

    private var background: Color {
        switch state {
        case .correct: .green.opacity(0.18)
        case .wrong: .red.opacity(0.18)
        default: Color.secondary.opacity(0.08)
        }
    }

    private var border: Color {
        switch state {
        case .correct: .green
        case .wrong: .red
        default: .clear
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
