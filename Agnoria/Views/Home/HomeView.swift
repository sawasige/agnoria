import SwiftUI
import SwiftData

/// ホーム（§4.1 [v1.4]）。役割は 2 つだけ: スクロール領域は状態を見る **ダッシュボード**（タップはすべて進捗へ）、
/// 画面下の固定バーは **学習開始**（おまかせ / 選んで始める）。ダッシュボードに学習開始の操作は置かない [v1.9]
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var typeSize

    @Query(filter: #Predicate<Word> { !$0.isArchived }) private var words: [Word]
    @Query(filter: #Predicate<GrammarQuestion> { !$0.isArchived }) private var grammar: [GrammarQuestion]
    @Query(filter: #Predicate<ListeningQuestion> { !$0.isArchived }) private var listening: [ListeningQuestion]
    @Query private var progress: [ItemProgress]
    @Query private var sessions: [StudySession]

    @State private var showSettings = false
    @State private var showStart = false
    @State private var showEmptyAlert = false

    private func items(_ mode: DrillMode) -> [(id: String, category: String)] {
        let enabled = settings.enabledLevels(mode)
        switch mode {
        case .word: return words.filter { enabled.contains($0.level) }.map { ($0.id, $0.category) }
        case .grammar: return grammar.filter { enabled.contains($0.level) }.map { ($0.id, $0.category) }
        case .listening: return listening.filter { enabled.contains($0.level) }.map { ($0.id, $0.category) }
        }
    }

    var body: some View {
        let pmap = Dictionary(progress.map { ($0.itemID, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
        // 復習の件数はおまかせ・復習の対象（単語・文法。切り替えがオンならリスニングも）[v1.9]
        let reviewItems = settings.autoModes.flatMap(items)
        let overall = MasteryStats.summarize(items: reviewItems, progress: pmap)
        let reviewIDs = reviewItems.map(\.id)
        let wrong = MasteryStats.wrongCount(itemIDs: reviewIDs, progress: pmap)
        let bookmarked = MasteryStats.bookmarkCount(itemIDs: reviewIDs, progress: pmap)
        let hasItems = !words.isEmpty || !grammar.isEmpty || !listening.isEmpty
        let tracks = Stage.tracks(items: [.word: words.map { (id: $0.id, level: $0.level) },
                                          .grammar: grammar.map { (id: $0.id, level: $0.level) },
                                          .listening: listening.map { (id: $0.id, level: $0.level) }],
                                  progress: pmap, unlocked: settings.unlockedLevels)
        let daily = MasteryStats.daily(sessions: sessions.map { ($0.finishedAt, $0.results) })
        let streak = Streak.compute(sessionDates: sessions.map(\.finishedAt))

        ScrollView {
            VStack(spacing: 16) {
                header

                if model.importState == .running, !hasItems {
                    ProgressView("問題データを準備中…")
                        .padding(.vertical, 40)
                } else if case .failed(let message) = model.importState, !hasItems {
                    ContentUnavailableView("問題データを読み込めません", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                } else {
                    Button {
                        model.path = [.stats]
                    } label: {
                        StageSummaryCard(tracks: tracks)
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
                        VStack(alignment: .leading, spacing: 10) {
                            DailyChart(days: daily, height: 110)
                            if overall.dueForReview > 0 || overall[.struggling] > 0 {
                                Text("復習待ち \(overall.dueForReview) ・ 苦手 \(overall[.struggling])")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("進捗の詳細を開く")
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AppBackground() }
        .safeAreaInset(edge: .bottom) {
            actionBar(tracks: tracks, disabled: !hasItems)
        }
        .navigationTitle("Agnoria")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Label("設定", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showStart) {
            StartSheet(tracks: tracks, wrong: wrong, bookmarked: bookmarked) { config in
                showStart = false
                start(config)
            }
        }
        .alert("出題できる問題がありません", isPresented: $showEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("設定の到達帯を広げるか、別の分野を選んでください。")
        }
    }

    // MARK: - ヘッダー

    /// アイコンと同じ女神の立ち絵をタイトルに添える。装飾なので画像は VoiceOver から隠す
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("AgenoriaPortrait")
                .resizable()
                .scaledToFit()
                .frame(height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agnoria")
                    .font(.system(size: 34, weight: .bold))
                Text("英単語・文法・リスニング 450〜600点")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.bottom, 2)
    }

    // MARK: - 下部の固定バー = 学習開始

    /// おまかせ（主）と、選んで始める（副。学習の選択シート §4.10）の 2 つだけ
    @ViewBuilder
    private func actionBar(tracks: [Stage.Track], disabled: Bool) -> some View {
        // 文字サイズがアクセシビリティ段階のときは横に並べず縦に積む（横だと文字が 1 字ずつ縦に折れる）
        let stacked = typeSize.isAccessibilitySize
        GlassEffectContainer(spacing: 10) {
            AnyLayout(stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
                Button {
                    start(.auto)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("おまかせで10問", systemImage: "sparkles")
                            .font(.headline)
                            .fontDesign(.rounded)
                        Text(autoHint(tracks))
                            .font(.caption)
                            .opacity(0.85)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(disabled)
                .accessibilityLabel("おまかせで10問。\(autoHint(tracks))")

                Button {
                    showStart = true
                } label: {
                    if stacked {
                        Label("選んで始める", systemImage: "list.bullet")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "list.bullet")
                                .font(.headline)
                            Text("選んで始める")
                                .font(.caption2)
                        }
                        .fixedSize()
                    }
                }
                .buttonStyle(.glass)
                .disabled(disabled)
                .accessibilityLabel("選んで始める")
                .accessibilityHint("単語・文法・リスニング・復習から選ぶ")
            }
            .controlSize(.large)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    /// 今のセットが何を中心に組まれるかの目安（おまかせに入る軸ごとの今の帯 [v1.8]。リスニングは切り替えがオンのとき）
    private func autoHint(_ tracks: [Stage.Track]) -> String {
        let auto = tracks.filter { settings.autoModes.contains($0.mode) }
        if auto.allSatisfy({ $0.summary.total == 0 }) { return "問題がありません" }
        // 同じ帯の軸はまとめる（「単語・文法 450・リスニング 500 点帯が中心」）。3 軸でも 1 行に収まりやすい
        var groups: [(level: Int, titles: [String])] = []
        for t in auto {
            if groups.last?.level == t.current { groups[groups.count - 1].titles.append(t.mode.title) }
            else { groups.append((t.current, [t.mode.title])) }
        }
        return groups.map { "\($0.titles.joined(separator: "・")) \($0.level)" }.joined(separator: "・") + " 点帯が中心"
    }

    private func start(_ config: QuizConfig) {
        if model.startQuiz(config) == nil { showEmptyAlert = true }
    }
}

// MARK: - ダッシュボードの部品

/// 3 つの軸の帯の進みを 1 枚にまとめたカード（§4.1 [v1.9]）。軸ごとに 軸名・今の帯・習得率・バー・4 帯の記号。
/// 末尾に、次の帯に一番近い軸の「あと N 問」を 1 行。クリアまでの目安は進捗画面（§4.6）
struct StageSummaryCard: View {
    let tracks: [Stage.Track]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 14) {
            ForEach(tracks) { track in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(track.mode.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(track.current) 点帯")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(track.summary.masteredPercent)%")
                            .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    AnyLayout(stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
                        MasteryBar(summary: track.summary, height: 8)
                        StageChips(state: { level in
                            if level > track.unlocked { return .locked }
                            if Stage.isCleared(track.byLevel[level] ?? MasterySummary()) { return .cleared }
                            return level == track.current ? .current : .open
                        })
                        .fixedSize()
                    }
                }
            }
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

    /// 次の帯に一番近い軸（残りの習得数が最少。0 は「進める」）。最上位をクリアした軸は対象外
    private var nextText: String {
        let candidates = tracks.compactMap { t -> (track: Stage.Track, next: Int, remaining: Int)? in
            guard let next = Stage.next(after: t.current) else { return nil }
            return (t, next, Stage.remainingToClear(t.summary))
        }
        guard let best = candidates.min(by: { $0.remaining < $1.remaining }) else {
            return "すべての帯をクリア。復習で定着させよう"
        }
        return best.remaining == 0
            ? "\(best.track.mode.title)は \(best.next) 点帯へ進めます"
            : "あと \(best.remaining) 問の習得で\(best.track.mode.title) \(best.next) 点帯へ"
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
