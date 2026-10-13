import SwiftUI
import Charts

/// 直近 2 週間の日別棒グラフ（回答数を薄く、正解数を濃く重ねる）。ホームと進捗画面で共用
struct DailyChart: View {
    let days: [DayStat]
    var height: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("この2週間").font(.headline)
                Spacer()
                let answered = days.reduce(0) { $0 + $1.answered }
                let correct = days.reduce(0) { $0 + $1.correct }
                Text("回答 \(answered) ・ 正解 \(correct)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Chart(days) { day in
                BarMark(x: .value("日", day.date, unit: .day), y: .value("回答", day.answered))
                    .foregroundStyle(Color.accentColor.opacity(0.25))
                    .cornerRadius(3)
                BarMark(x: .value("日", day.date, unit: .day), y: .value("正解", day.correct))
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            }
            .chartYAxis { AxisMarks(position: .trailing) }
            .frame(height: height)
            .accessibilityLabel("日別の回答数と正解数")
        }
    }
}
