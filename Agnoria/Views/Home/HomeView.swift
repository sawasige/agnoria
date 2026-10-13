import SwiftUI
import SwiftData

/// ホーム（§4.1 [v1.4]）。状態を見るダッシュボード。学習の入口は画面下の固定バーだけ
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @Query(filter: #Predicate<Word> { !$0.isArchived }) private var words: [Word]
    @Query(filter: #Predicate<GrammarQuestion> { !$0.isArchived }) private var grammar: [GrammarQuestion]
    @Query private var progress: [ItemProgress]
    @Query private var sessions: [StudySession]

    @State private var showSettings = false
    @State private var showEmptyAlert = false

    private var wordItems: [(id: String, category: String)] {
        words.filter { settings.enabledLevels.contains($0.level) }.map { ($0.id, $0.category) }
    }
    private var grammarItems: [(id: String, category: String)] {
        grammar.filter { settings.enabledLevels.contains($0.level) }.map { ($0.id, $0.category) }
    }

    var body: some View {
        let pmap = Dictionary(progress.map { ($0.itemID, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
        let allItems = wordItems + grammarItems
        let overall = MasteryStats.summarize(items: allItems, progress: pmap)
        let allIDs = allItems.map(\.id)
        let wrong = MasteryStats.wrongCount(itemIDs: allIDs, progress: pmap)
        let bookmarked = MasteryStats.bookmarkCount(itemIDs: allIDs, progress: pmap)
        let byLevel = MasteryStats.byLevel(items: words.map { (id: $0.id, level: $0.level) }
                                           + grammar.map { (id: $0.id, level: $0.level) }, progress: pmap)
        let stage = Stage.current(unlocked: settings.unlockedLevel, byLevel: byLevel)
        let stageSummary = byLevel[stage] ?? MasterySummary()
        let daily = MasteryStats.daily(sessions: sessions.map { ($0.finishedAt, $0.results) })
        let streak = Streak.compute(sessionDates: sessions.map(\.finishedAt))
        let showReview = overall.dueForReview > 0 || overall[.struggling] > 0 || wrong > 0 || bookmarked > 0

        ScrollView {
            VStack(spacing: 16) {
                if model.importState == .running, allItems.isEmpty {
                    ProgressView("問題データを準備中…")
                        .padding(.vertical, 40)
                } else if case .failed(let message) = model.importState, allItems.isEmpty {
                    ContentUnavailableView("問題データを読み込めません", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                } else {
                    Button {
                        model.path = [.stats]
                    } label: {
                        StageCard(stage: stage, unlocked: settings.unlockedLevel, byLevel: byLevel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("進捗の詳細を開く")

                    HStack(spacing: 12) {
                        StreakCard(streak: streak)
                        TodayCard(today: daily.last)
                    }

                    Button {
                        model.path = [.stats]
                    } label: {
                        DailyChart(days: daily, height: 110)
                            .glassCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("進捗の詳細を開く")

                    if showReview {
                        ReviewCard(dueForReview: overall.dueForReview, struggling: overall[.struggling],
                                   wrong: wrong, bookmarked: bookmarked) { filter in
                            start(QuizConfig(mode: nil, category: nil, format: nil, filter: filter))
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AppBackground() }
        .safeAreaInset(edge: .bottom) {
            actionBar(stage: stage, stageSummary, disabled: allItems.isEmpty)
        }
        .navigationTitle("Agnoria")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Label("設定", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("出題できる問題がありません", isPresented: $showEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("設定の到達帯を広げるか、分野を選んでください。")
        }
    }

    // MARK: - 下部の固定バー

    /// 画面下に固定する学習の入口。おまかせ（主）と分野を選ぶ（副）
    @ViewBuilder
    private func actionBar(stage: Int, _ summary: MasterySummary, disabled: Bool) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    start(.auto)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("おまかせで10問", systemImage: "sparkles")
                            .font(.headline)
                            .fontDesign(.rounded)
                        Text(autoHint(stage: stage, summary))
                            .font(.caption)
                            .opacity(0.85)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(disabled)
                .accessibilityLabel("おまかせで10問。\(autoHint(stage: stage, summary))")

                Button {
                    model.path = [.pick]
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "square.grid.2x2")
                            .font(.headline)
                        Text("分野")
                            .font(.caption)
                    }
                    .frame(minWidth: 52)
                }
                .buttonStyle(.glass)
                .disabled(disabled)
                .accessibilityLabel("分野を選ぶ")
            }
            .controlSize(.large)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    /// 今のセットが何を中心に組まれるかの目安（今のステージの内訳）
    private func autoHint(stage: Int, _ s: MasterySummary) -> String {
        if s.total == 0 { return "問題がありません" }
        if s[.struggling] == 0, s[.unseen] == 0, s.dueForReview == 0 {
            return "\(stage) 点帯は全部習得済み。復習で定着させよう"
        }
        return "\(stage) 点帯: 苦手 \(s[.struggling])・未学習 \(s[.unseen])・復習 \(s.dueForReview)"
    }

    private func start(_ config: QuizConfig) {
        if model.startQuiz(config) == nil { showEmptyAlert = true }
    }
}

// MARK: - ウィジェット

/// 今の帯の習得率・積み上げバー・次の帯まで・4 帯のミニ表示
struct StageCard: View {
    let stage: Int
    let unlocked: Int
    let byLevel: [Int: MasterySummary]

    private var summary: MasterySummary { byLevel[stage] ?? MasterySummary() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(stage) 点帯の習得")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(summary.masteredPercent)")
                            .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.title3.weight(.semibold))
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                stageRow
            }
            MasteryBar(summary: summary, height: 12)
            HStack {
                Text(nextText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    /// 4 帯の状態を横に並べる: クリア済み ✓ / 今の帯 ● / 開いている ○ / 未到達 🔒
    private var stageRow: some View {
        HStack(spacing: 10) {
            ForEach(Stage.levels, id: \.self) { level in
                let s = byLevel[level] ?? MasterySummary()
                let locked = level > unlocked
                let cleared = !locked && Stage.isCleared(s)
                VStack(spacing: 3) {
                    Image(systemName: locked ? "lock.fill"
                          : cleared ? "checkmark.circle.fill"
                          : level == stage ? "record.circle" : "circle")
                        .font(.footnote)
                        .foregroundStyle(locked ? Color.secondary.opacity(0.5)
                                         : cleared ? Color.green : Color.accentColor)
                    Text("\(level)")
                        .font(.caption2.monospacedDigit())
                        .fontWeight(level == stage ? .bold : .regular)
                        .foregroundStyle(level == stage ? Color.primary : Color.secondary)
                }
            }
        }
        .padding(.top, 4)
        .accessibilityLabel(Stage.levels.map { level in
            let locked = level > unlocked
            let cleared = !locked && Stage.isCleared(byLevel[level] ?? MasterySummary())
            return "\(level) 点帯 " + (locked ? "未到達" : cleared ? "クリア" : level == stage ? "今ここ" : "学習中")
        }.joined(separator: "、"))
    }

    private var nextText: String {
        if let next = Stage.next(after: stage) {
            let remaining = Stage.remainingToClear(summary)
            return remaining == 0
                ? "\(next) 点帯へ進めます"
                : "あと \(remaining) 問の習得で \(next) 点帯へ"
        }
        return Stage.isCleared(summary) ? "最上位の帯をクリア。復習で定着させよう" : "最上位の帯。ここを仕上げよう"
    }
}

/// 連続学習日数。今日まだやっていなければ目立たせる
struct StreakCard: View {
    let streak: Streak.Result

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("連続")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(streak.doneToday ? Color.orange : Color.secondary)
                Text("\(streak.days)")
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("日")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
            }
            Text(streak.doneToday ? "今日も学習済み" : "今日はまだ")
                .font(.caption)
                .fontWeight(streak.doneToday ? .regular : .semibold)
                .foregroundStyle(streak.doneToday ? Color.secondary : Color.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

/// 今日の回答数と正解率
struct TodayCard: View {
    let today: DayStat?

    private var answered: Int { today?.answered ?? 0 }
    private var accuracy: Int? {
        guard let today, today.answered > 0 else { return nil }
        return Int((Double(today.correct) / Double(today.answered) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(answered)")
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("問")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
            }
            Text(accuracy.map { "正解率 \($0)%" } ?? "1 セット 10 問から")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

/// 復習の入口。復習待ち・苦手の件数と、間違えた問題 / ブックマークのボタン
struct ReviewCard: View {
    let dueForReview: Int
    let struggling: Int
    let wrong: Int
    let bookmarked: Int
    let start: (DrillFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("復習", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                Text("復習待ち \(dueForReview) ・ 苦手 \(struggling)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { start(.wrongOnly) } label: {
                    Label("間違えた \(wrong)", systemImage: "arrow.counterclockwise")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .disabled(wrong == 0)

                Button { start(.bookmarked) } label: {
                    Label("ブックマーク \(bookmarked)", systemImage: "bookmark")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .disabled(bookmarked == 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .glassCard()
    }
}
