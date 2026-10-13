import SwiftUI
import SwiftData
import Charts

/// 進捗画面（§4.6 [v1.2]）。達成度（習得の内訳）と推移（日別の学習量）
struct StatsView: View {
    @Environment(AppSettings.self) private var settings

    @Query(filter: #Predicate<Word> { !$0.isArchived }) private var words: [Word]
    @Query(filter: #Predicate<GrammarQuestion> { !$0.isArchived }) private var grammar: [GrammarQuestion]
    @Query private var progress: [ItemProgress]
    @Query(sort: \StudySession.finishedAt) private var sessions: [StudySession]

    var body: some View {
        let pmap = Dictionary(progress.map { ($0.itemID, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
        let wordItems = words.filter { settings.enabledLevels.contains($0.level) }.map { (id: $0.id, category: $0.category) }
        let grammarItems = grammar.filter { settings.enabledLevels.contains($0.level) }.map { (id: $0.id, category: $0.category) }
        let overall = MasteryStats.summarize(items: wordItems + grammarItems, progress: pmap)
        let daily = MasteryStats.daily(sessions: sessions.map { ($0.finishedAt, $0.results) })
        let streak = Streak.compute(sessionDates: sessions.map(\.finishedAt))

        ScrollView {
            VStack(spacing: 16) {
                overview(overall, streak: streak)
                dailyChart(daily)
                categoryChart(title: "単語", mode: .word, items: wordItems, progress: pmap)
                categoryChart(title: "文法", mode: .grammar, items: grammarItems, progress: pmap)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AppBackground() }
        .navigationTitle("進捗")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 達成度

    private func overview(_ s: MasterySummary, streak: Streak.Result) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("習得")
                    .font(.headline)
                Text("\(s.masteredPercent)%")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(s[.mastered]) / \(s.total) 問")
                    Text("正答率 \(s.accuracyPercent.map { "\($0)%" } ?? "--")")
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            MasteryBar(summary: s, height: 14)
            MasteryLegend(summary: s)
            Divider()
            HStack(spacing: 24) {
                stat("累計回答", "\(s.answered)")
                stat("累計正解", "\(s.correct)")
                stat("連続日数", "\(streak.days)日")
                stat("復習待ち", "\(s.dueForReview)")
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).fontDesign(.rounded)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 推移

    private func dailyChart(_ days: [DayStat]) -> some View {
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
            .frame(height: 150)
            .accessibilityLabel("日別の回答数と正解数")
        }
        .glassCard()
    }

    // MARK: - 分野別

    private func categoryChart(title: String, mode: DrillMode, items: [(id: String, category: String)],
                               progress: [String: ProgressSnapshot]) -> some View {
        let byCat = MasteryStats.byCategory(items: items, progress: progress)
        let categories = mode.categories
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Chart {
                ForEach(categories, id: \.self) { cat in
                    let s = byCat[cat] ?? MasterySummary()
                    ForEach(Mastery.barOrder, id: \.self) { m in
                        BarMark(x: .value("件数", s[m]), y: .value("分野", cat))
                            .foregroundStyle(by: .value("段階", m.title))
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: Mastery.barOrder.map(\.title),
                range: Mastery.barOrder.map(\.color)
            )
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) { _ in
                    AxisValueLabel()
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartLegend(.hidden)
            .frame(height: CGFloat(categories.count) * 34 + 24)
            .accessibilityLabel("\(title)の分野別の習得状況")
        }
        .glassCard()
    }
}
