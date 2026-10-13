import SwiftUI

/// 分野タイル: アイコン・習得率・積み上げバー
struct CategoryTile: View {
    let title: String
    let stats: MasterySummary
    var isMix = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Image(systemName: isMix ? "square.grid.2x2.fill" : DrillMode.symbol(for: title))
                        .font(.title3)
                        .foregroundStyle(isMix ? Color.accentColor : Color.secondary)
                        .frame(width: 28, alignment: .leading)
                    Spacer()
                    Text(stats.total == 0 ? "--" : "\(stats.masteredPercent)%")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                MasteryBar(summary: stats, height: 6)
                Text("習得 \(stats[.mastered]) / \(stats.total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            .glassEffect(isMix ? .regular.tint(Color.accentColor.opacity(0.3)).interactive() : .regular.interactive(),
                         in: .rect(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(stats.total == 0)
        .opacity(stats.total == 0 ? 0.4 : 1)
        .accessibilityLabel("\(title)。習得 \(stats[.mastered]) 件、全 \(stats.total) 件")
    }
}
