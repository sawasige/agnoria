import SwiftUI
import SwiftData

/// 分野を選ぶ（§4.7 [v1.4]）。単語 / 文法 / リスニング [v1.9] → 出題形式（単語のみ）→ 分野タイル。ホームから切り出した
struct PickView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @Query(filter: #Predicate<Word> { !$0.isArchived }) private var words: [Word]
    @Query(filter: #Predicate<GrammarQuestion> { !$0.isArchived }) private var grammar: [GrammarQuestion]
    @Query(filter: #Predicate<ListeningQuestion> { !$0.isArchived }) private var listening: [ListeningQuestion]
    @Query private var progress: [ItemProgress]

    @State private var mode: DrillMode = .word
    @State private var formatChoice: FormatChoice = .random
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

    private var items: [(id: String, category: String)] {
        switch mode {
        case .word: words.filter { settings.enabledLevels(.word).contains($0.level) }.map { ($0.id, $0.category) }
        case .grammar: grammar.filter { settings.enabledLevels(.grammar).contains($0.level) }.map { ($0.id, $0.category) }
        case .listening: listening.filter { settings.enabledLevels(.listening).contains($0.level) }.map { ($0.id, $0.category) }
        }
    }

    var body: some View {
        let pmap = Dictionary(progress.map { ($0.itemID, $0.snapshot) }, uniquingKeysWith: { a, _ in a })
        let stats = MasteryStats.byCategory(items: items, progress: pmap)

        ScrollView {
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
                .padding(.top, 4)

                Text("\(mode.title)は \(settings.unlockedLevel(mode)) 点帯までの問題から 10 問。到達帯は設定で変えられます")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if mode == .listening {
                    Label("問いかけと応答を音声で出します。音の出せる場所で", systemImage: "speaker.wave.2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AppBackground() }
        .navigationTitle("分野を選ぶ")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("出題できる問題がありません", isPresented: $showEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("設定の到達帯を広げるか、別の分野を選んでください。")
        }
    }

    private func start(_ config: QuizConfig) {
        if model.startQuiz(config) == nil { showEmptyAlert = true }
    }
}
