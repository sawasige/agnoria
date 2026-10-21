import SwiftUI
import SwiftData

/// ホーム（§4.1 [v1.4]）。状態を見るダッシュボード。学習の入口は画面下の固定バーだけ
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
    @State private var showEmptyAlert = false

    private var wordItems: [(id: String, category: String)] {
        let enabled = settings.enabledLevels(.word)
        return words.filter { enabled.contains($0.level) }.map { ($0.id, $0.category) }
    }
    private var grammarItems: [(id: String, category: String)] {
        let enabled = settings.enabledLevels(.grammar)
        return grammar.filter { enabled.contains($0.level) }.map { ($0.id, $0.category) }
    }
    private var listeningItems: [(id: String, category: String)] {
        let enabled = settings.enabledLevels(.listening)
        return listening.filter { enabled.contains($0.level) }.map { ($0.id, $0.category) }
    }

    var body: some View {
        let pmap = Dictionary(progress.map { ($0.itemID, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
        // 復習カードの件数はおまかせ・復習の対象（単語・文法）だけ。リスニングは分野画面から [v1.9]
        let allItems = wordItems + grammarItems
        let overall = MasteryStats.summarize(items: allItems, progress: pmap)
        let allIDs = allItems.map(\.id)
        let wrong = MasteryStats.wrongCount(itemIDs: allIDs, progress: pmap)
        let bookmarked = MasteryStats.bookmarkCount(itemIDs: allIDs, progress: pmap)
        let tracks = Stage.tracks(items: [.word: words.map { (id: $0.id, level: $0.level) },
                                          .grammar: grammar.map { (id: $0.id, level: $0.level) },
                                          .listening: listening.map { (id: $0.id, level: $0.level) }],
                                  progress: pmap, unlocked: settings.unlockedLevels)
        let daily = MasteryStats.daily(sessions: sessions.map { ($0.finishedAt, $0.results) })
        let streak = Streak.compute(sessionDates: sessions.map(\.finishedAt))
        let estimates = estimates(tracks)
        let showReview = overall.dueForReview > 0 || overall[.struggling] > 0 || wrong > 0 || bookmarked > 0

        ScrollView {
            VStack(spacing: 16) {
                header

                if model.importState == .running, allItems.isEmpty {
                    ProgressView("問題データを準備中…")
                        .padding(.vertical, 40)
                } else if case .failed(let message) = model.importState, allItems.isEmpty {
                    ContentUnavailableView("問題データを読み込めません", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                } else {
                    ForEach(tracks) { track in
                        Button {
                            model.path = [.stats]
                        } label: {
                            StageCard(track: track, estimate: estimates[track.mode])
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("進捗の詳細を開く")
                    }

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
            actionBar(tracks: tracks, disabled: allItems.isEmpty)
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
        .alert("出題できる問題がありません", isPresented: $showEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("設定の到達帯を広げるか、分野を選んでください。")
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

    // MARK: - 下部の固定バー

    /// 画面下に固定する学習の入口。おまかせ（主）と分野を選ぶ（副）
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(disabled)
                .accessibilityLabel("おまかせで10問。\(autoHint(tracks))")

                Button {
                    model.path = [.pick]
                } label: {
                    if stacked {
                        Label("分野を選ぶ", systemImage: "square.grid.2x2")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "square.grid.2x2")
                                .font(.headline)
                            Text("分野")
                                .font(.caption)
                        }
                        .frame(minWidth: 52)
                    }
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

    /// 今のセットが何を中心に組まれるかの目安（おまかせに入る軸ごとの今の帯 [v1.8]）
    private func autoHint(_ tracks: [Stage.Track]) -> String {
        let auto = tracks.filter { DrillMode.autoModes.contains($0.mode) }
        if auto.allSatisfy({ $0.summary.total == 0 }) { return "問題がありません" }
        return auto.map { "\($0.mode.title) \($0.current)" }.joined(separator: "・") + " 点帯が中心"
    }

    /// 軸ごとのクリアまでの目安。1 セットに占める割合は、到達帯までの問題数の比で見込む
    private func estimates(_ tracks: [Stage.Track]) -> [DrillMode: Pace.Estimate] {
        let idsByMode: [DrillMode: Set<String>] = [.word: Set(wordItems.map(\.id)), .grammar: Set(grammarItems.map(\.id)),
                                                   .listening: Set(listeningItems.map(\.id))]

        let total = Double(idsByMode.values.reduce(0) { $0 + $1.count })
        let sessionDates = sessions.map(\.finishedAt)
        var out: [DrillMode: Pace.Estimate] = [:]
        for track in tracks {
            let ids = idsByMode[track.mode] ?? []
            guard total > 0, !ids.isEmpty else { continue }
            out[track.mode] = Pace.estimate(remaining: Stage.remainingToClear(track.summary),
                                            masteredDates: progress.filter { ids.contains($0.itemID) }.compactMap(\.masteredAt),
                                            sessionDates: sessionDates, share: Double(ids.count) / total)
        }
        return out
    }

    private func start(_ config: QuizConfig) {
        if model.startQuiz(config) == nil { showEmptyAlert = true }
    }
}

// MARK: - ウィジェット

/// 1 つの軸の今の帯の習得率・積み上げバー・次の帯まで・4 帯のミニ表示（軸ごとに 1 枚 [v1.8]）
struct StageCard: View {
    let track: Stage.Track
    /// クリアまでの目安（§4.1）。クリア済みなら nil
    var estimate: Pace.Estimate? = nil

    private var stage: Int { track.current }
    private var summary: MasterySummary { track.summary }
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // アクセシビリティ文字サイズでは見出しと帯の並びを縦に積む
        let stacked = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 12) {
            AnyLayout(stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top))) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(track.mode.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(stage) 点帯の習得")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(summary.masteredPercent)")
                            .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.title3.weight(.semibold))
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                }
                if !stacked { Spacer() }
                stageRow
            }
            MasteryBar(summary: summary, height: 12)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nextText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    if let estimateText {
                        Text(estimateText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    /// 4 帯の状態を横に並べる（StageChips）
    private var stageRow: some View {
        StageChips(state: { level in
            if level > track.unlocked { return .locked }
            if Stage.isCleared(track.byLevel[level] ?? MasterySummary()) { return .cleared }
            return level == stage ? .current : .open
        })
        .padding(.top, 4)
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

    /// 「目安 約 40 セット・今のペースなら約 8 日」。まだ学習していなければセット数と 1 セットの所要時間だけ
    private var estimateText: String? {
        guard let estimate else { return nil }
        if let days = estimate.days {
            return "目安 約 \(estimate.sets) セット・今のペースなら\(Pace.daysText(days))"
        }
        return "目安 約 \(estimate.sets) セット（1 セット 3〜4 分）"
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
