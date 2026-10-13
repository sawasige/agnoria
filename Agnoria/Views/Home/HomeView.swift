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
            VStack(spacing: 20) {
                StreakHeader(streak: Streak.compute(sessionDates: sessions.map(\.finishedAt)),
                             totalCorrect: totalCorrect)

                Button {
                    start(.auto)
                } label: {
                    VStack(spacing: 4) {
                        Label("おまかせで10問", systemImage: "sparkles")
                            .font(.headline)
                        Text("苦手 \(overall[.struggling])・未学習 \(overall[.unseen])・復習 \(overall.dueForReview)")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(allItems.isEmpty)

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

                if model.importState == .running, items.isEmpty {
                    ProgressView("問題データを準備中…")
                        .padding(.vertical, 40)
                } else if case .failed(let message) = model.importState, items.isEmpty {
                    ContentUnavailableView("問題データを読み込めません", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                } else {
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
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
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
            Text("設定の出題レベルを広げるか、別の分野を選んでください。")
        }
    }

    private func start(_ config: QuizConfig) {
        if model.startQuiz(config) == nil { showEmptyAlert = true }
    }
}

struct StreakHeader: View {
    let streak: Streak.Result
    let totalCorrect: Int

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Rank.title(totalCorrect: totalCorrect))
                    .font(.headline)
                Text(Rank.subtitle(totalCorrect: totalCorrect))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text("\(streak.days)日")
                }
                .font(.headline)
                .foregroundStyle(streak.doneToday ? Color.orange : Color.secondary)
                Text(streak.doneToday ? "今日も学習済み" : "今日はまだ")
                    .font(.caption)
                    .fontWeight(streak.doneToday ? .regular : .semibold)
                    .foregroundStyle(streak.doneToday ? Color.secondary : Color.orange)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CategoryTile: View {
    let title: String
    let stats: MasterySummary
    var isMix = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Text(stats.accuracyPercent.map { "\($0)%" } ?? "--")
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Spacer()
                    Text("習得 \(stats[.mastered]) / \(stats.total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(isMix ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(stats.total == 0)
        .opacity(stats.total == 0 ? 0.4 : 1)
        .accessibilityLabel("\(title)。正答率 \(stats.accuracyPercent.map { "\($0)パーセント" } ?? "未学習")。習得 \(stats[.mastered]) 件、全 \(stats.total) 件")
    }
}
