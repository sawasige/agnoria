import SwiftUI

extension Mastery {
    /// 独自色はこの4色と正誤の緑／赤のみ（§7）
    var color: Color {
        switch self {
        case .mastered: .green
        case .learning: .accentColor
        case .struggling: .orange
        case .unseen: Color.gray.opacity(0.35)
        }
    }

    /// 積み上げバーの並び順（左から）
    static let barOrder: [Mastery] = [.mastered, .learning, .struggling, .unseen]
}

/// 4段階の積み上げバー。件数比で幅を割る
struct MasteryBar: View {
    let summary: MasterySummary
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: summary.total > 1 ? 2 : 0) {
                ForEach(Mastery.barOrder, id: \.self) { m in
                    if summary[m] > 0 {
                        Rectangle()
                            .fill(m.color)
                            .frame(width: max(2, geo.size.width * CGFloat(summary[m]) / CGFloat(max(summary.total, 1))))
                    }
                }
            }
        }
        .frame(height: height)
        .background(Color.gray.opacity(0.15))
        .clipShape(Capsule())
        .animation(.spring(duration: 0.6), value: summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        Mastery.barOrder.map { "\($0.title) \(summary[$0]) 件" }.joined(separator: "、")
    }
}

/// 凡例（色の丸＋名前＋件数）
struct MasteryLegend: View {
    let summary: MasterySummary

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Mastery.barOrder, id: \.self) { m in
                HStack(spacing: 5) {
                    Circle().fill(m.color).frame(width: 8, height: 8)
                    Text(m.title)
                    Text("\(summary[m])").monospacedDigit().fontWeight(.semibold)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
