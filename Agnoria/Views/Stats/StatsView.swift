import SwiftUI
import SwiftData
import Charts

/// 進捗画面（§4.6 [v1.2]）。達成度（習得の内訳）と推移（日別の学習量）
struct StatsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model

    @Query private var progress: [ItemProgress]
    @Query(sort: \StudySession.finishedAt) private var sessions: [StudySession]

    var body: some View {
        let pmap = Dictionary(progress.map { ($0.itemID, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
        let catalog = model.catalog
        let wordItems = catalog.categoryItems(.word, levels: settings.enabledLevels(.word))
        let grammarItems = catalog.categoryItems(.grammar, levels: settings.enabledLevels(.grammar))
        let listeningItems = catalog.categoryItems(.listening, levels: settings.enabledLevels(.listening))
        let overall = MasteryStats.summarize(items: wordItems + grammarItems + listeningItems, progress: pmap)
        let tracks = Stage.tracks(items: catalog.levelItemsByMode, progress: pmap, unlocked: settings.unlockedLevels, floor: settings.startingLevel)

        let daily = MasteryStats.daily(sessions: sessions.map { ($0.finishedAt, $0.results) })
        let streak = Streak.compute(sessionDates: sessions.map(\.finishedAt))
        let totalCorrect = progress.reduce(0) { $0 + $1.totalCorrect }
        // クリアまでの目安（§4.1 → §4.6 [v1.9]）
        let estimates = Pace.estimates(
            tracks: tracks,
            idsByMode: [.word: Set(wordItems.map(\.id)), .grammar: Set(grammarItems.map(\.id)), .listening: Set(listeningItems.map(\.id))],
            masteredAt: Dictionary(progress.compactMap { p in p.masteredAt.map { (p.itemID, $0) } }, uniquingKeysWith: { a, _ in a }),
            sessionDates: sessions.map(\.finishedAt))

        ScrollView {
            VStack(spacing: 16) {
                overview(overall, streak: streak, totalCorrect: totalCorrect)
                stageRows(tracks, estimates: estimates)
                DailyChart(days: daily)
                    .glassCard()
                categoryChart(title: "単語", mode: .word, items: wordItems, progress: pmap)
                categoryChart(title: "文法", mode: .grammar, items: grammarItems, progress: pmap)
                categoryChart(title: "リスニング", mode: .listening, items: listeningItems, progress: pmap)
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

    private func overview(_ s: MasterySummary, streak: Streak.Result, totalCorrect: Int) -> some View {
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
            HStack(spacing: 4) {
                Image(systemName: "laurel.leading")
                    .foregroundStyle(.secondary)
                Text(Rank.title(totalCorrect: totalCorrect))
                    .font(.caption.weight(.semibold))
                Text("・ " + Rank.subtitle(totalCorrect: totalCorrect))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - ステージ

    /// 軸ごとに 4 帯の行を並べる [v1.8]。見出しの横に「あと N 問」、下にクリアまでの目安 [v1.9]
    private func stageRows(_ tracks: [Stage.Track], estimates: [DrillMode: Pace.Estimate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ステージ").font(.headline)
            ForEach(tracks) { track in
                HStack(alignment: .firstTextBaseline) {
                    Text(track.mode.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(nextText(track))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.top, track.mode == tracks.first?.mode ? 0 : 6)
                levelRows(byLevel: track.byLevel, current: track.current, unlocked: track.unlocked, title: track.mode.title)
                if let e = estimates[track.mode] {
                    Text(Pace.text(e))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text("単語・文法・リスニングそれぞれ、習得率 80% で次の帯が開きます")

                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func nextText(_ track: Stage.Track) -> String {
        if let next = Stage.next(after: track.current) {
            let remaining = Stage.remainingToClear(track.summary)
            return remaining == 0 ? "\(next) 点帯へ進めます" : "あと \(remaining) 問で \(next) 点帯へ"
        }
        return Stage.isCleared(track.summary) ? "最上位をクリア" : "最上位の帯"
    }

    @ViewBuilder
    private func levelRows(byLevel: [Int: MasterySummary], current: Int, unlocked: Int, title: String) -> some View {

            ForEach(Stage.levels, id: \.self) { level in
                let s = byLevel[level] ?? MasterySummary()
                let locked = level > unlocked
                HStack(spacing: 10) {
                    Image(systemName: locked ? "lock.fill" : (Stage.isCleared(s) ? "checkmark.circle.fill" : "circle"))
                        .foregroundStyle(locked ? Color.secondary : (Stage.isCleared(s) ? Color.green : Color.accentColor))
                        .frame(width: 20)
                    Text("\(level) 点帯")
                        .font(.subheadline.weight(level == current && !locked ? .semibold : .regular))
                        .frame(width: 72, alignment: .leading)
                    MasteryBar(summary: s, height: 8)
                        .opacity(locked ? 0.4 : 1)
                    Text(locked ? "未到達" : "\(s[.mastered]) / \(s.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title) \(level)点帯。\(locked ? "未到達" : "習得 \(s[.mastered]) / \(s.total)")\(level == current ? "。今ここ" : "")")
            }
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
