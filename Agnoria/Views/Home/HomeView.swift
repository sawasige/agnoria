import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @Query(filter: #Predicate<Word> { !$0.isArchived }) private var words: [Word]
    @Query(filter: #Predicate<GrammarQuestion> { !$0.isArchived }) private var grammar: [GrammarQuestion]
    @Query private var progress: [ItemProgress]
    @Query private var sessions: [StudySession]

    @State private var mode: DrillMode = .word
    @State private var formatChoice: FormatChoice = .random
    @State private var showManual = true
    @State private var showSettings = false
    @State private var showEmptyAlert = false

    enum FormatChoice: Hashable, CaseIterable {
        case meaning, cloze, jaToEn, random
        var title: String {
            switch self {
            case .meaning: WordFormat.meaning.title
            case .cloze: WordFormat.cloze.title
            case .jaToEn: WordFormat.jaToEn.title
            case .random: "ランダム"
            }
        }
        var format: WordFormat? {
            switch self {
            case .meaning: .meaning
            case .cloze: .cloze
            case .jaToEn: .jaToEn
            case .random: nil
            }
        }
    }

    private var progressMap: [String: ProgressSnapshot] {
        Dictionary(progress.map { ($0.itemID, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
    }

    private var wordItems: [(id: String, category: String)] {
        words.filter { settings.enabledLevels.contains($0.level) }.map { ($0.id, $0.category) }
    }
    private var grammarItems: [(id: String, category: String)] {
        grammar.filter { settings.enabledLevels.contains($0.level) }.map { ($0.id, $0.category) }
    }
    private var items: [(id: String, category: String)] {
        mode == .word ? wordItems : grammarItems
    }

    var body: some View {
        let pmap = progressMap
        let items = items
        let allItems = wordItems + grammarItems
        let stats = MasteryStats.byCategory(items: items, progress: pmap)
        let overall = MasteryStats.summarize(items: allItems, progress: pmap)
        let allIDs = allItems.map(\.id)
        let wrong = MasteryStats.wrongCount(itemIDs: allIDs, progress: pmap)
        let bookmarked = MasteryStats.bookmarkCount(itemIDs: allIDs, progress: pmap)
        let totalCorrect = progress.reduce(0) { $0 + $1.totalCorrect }

        ScrollView {
            VStack(spacing: 16) {
                Button {
                    model.path = [.stats]
                } label: {
                    MasteryCard(summary: overall,
                                streak: Streak.compute(sessionDates: sessions.map(\.finishedAt)),
                                totalCorrect: totalCorrect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("進捗の詳細を開く")

                if model.importState == .running, allItems.isEmpty {
                    ProgressView("問題データを準備中…")
                        .padding(.vertical, 40)
                } else if case .failed(let message) = model.importState, allItems.isEmpty {
                    ContentUnavailableView("問題データを読み込めません", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                } else {
                    autoButton(overall, disabled: allItems.isEmpty)
                    manualSection(stats: stats)
                    reviewButtons(wrong: wrong, bookmarked: bookmarked)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AppBackground() }
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
            Text("設定の出題レベルを広げるか、別の分野を選んでください。")
        }
    }

    // MARK: - おまかせ

    private func autoButton(_ overall: MasterySummary, disabled: Bool) -> some View {
        Button {
            start(.auto)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("おまかせで10問")
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                    Text(autoHint(overall))
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .opacity(0.7)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(disabled)
        .accessibilityLabel("おまかせで10問。\(autoHint(overall))")
    }

    /// 今のセットが何を中心に組まれるかの目安
    private func autoHint(_ s: MasterySummary) -> String {
        if s.total == 0 { return "問題がありません" }
        if s[.struggling] == 0, s[.unseen] == 0, s.dueForReview == 0 {
            return "全部習得済み。復習で定着させよう"
        }
        return "苦手 \(s[.struggling])・未学習 \(s[.unseen])・復習 \(s.dueForReview)"
    }

    // MARK: - 分野を選んで学ぶ

    private func manualSection(stats: [String: MasterySummary]) -> some View {
        DisclosureGroup(isExpanded: $showManual) {
            VStack(spacing: 12) {
                Picker("モード", selection: $mode) {
                    ForEach(DrillMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .word {
                    Picker("出題形式", selection: $formatChoice) {
                        ForEach(FormatChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("出題形式")
                }

                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(mode.categories, id: \.self) { category in
                            CategoryTile(title: category, stats: stats[category] ?? MasterySummary()) {
                                start(QuizConfig(mode: mode, category: category, format: formatChoice.format))
                            }
                        }
                        CategoryTile(title: "ミックス", stats: stats.values.reduce(MasterySummary(), +), isMix: true) {
                            start(QuizConfig(mode: mode, category: nil, format: formatChoice.format))
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("分野を選んで学ぶ", systemImage: "square.grid.2x2")
                .font(.headline)
        }
        .tint(.primary)
        .padding(.top, 4)
    }

    private func reviewButtons(wrong: Int, bookmarked: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                start(QuizConfig(mode: nil, category: nil, format: nil, filter: .wrongOnly))
            } label: {
                Label("間違えた問題 (\(wrong))", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .disabled(wrong == 0)

            Button {
                start(QuizConfig(mode: nil, category: nil, format: nil, filter: .bookmarked))
            } label: {
                Label("ブックマーク (\(bookmarked))", systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .disabled(bookmarked == 0)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    private func start(_ config: QuizConfig) {
        if model.startQuiz(config) == nil { showEmptyAlert = true }
    }
}

/// 学習状況のカード: 習得率・積み上げバー・連続日数・称号
struct MasteryCard: View {
    let summary: MasterySummary
    let streak: Streak.Result
    let totalCorrect: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("習得")
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
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text("\(streak.days)日")
                            .monospacedDigit()
                    }
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(streak.doneToday ? Color.orange : Color.secondary)
                    Text(streak.doneToday ? "今日も学習済み" : "今日はまだ")
                        .font(.caption)
                        .fontWeight(streak.doneToday ? .regular : .semibold)
                        .foregroundStyle(streak.doneToday ? Color.secondary : Color.orange)
                }
            }
            MasteryBar(summary: summary, height: 12)
            MasteryLegend(summary: summary)
            HStack(spacing: 4) {
                Text(Rank.title(totalCorrect: totalCorrect))
                    .font(.caption.weight(.semibold))
                Text("・ " + Rank.subtitle(totalCorrect: totalCorrect))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

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
