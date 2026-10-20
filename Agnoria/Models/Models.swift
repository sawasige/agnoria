import Foundation
import SwiftData

@Model
final class GrammarQuestion {
    @Attribute(.unique) var id: String
    var category: String
    var question: String
    /// 空欄を正解で埋めた文の和訳 [v1.7]。既定値は軽量マイグレーション用
    var questionJa: String = ""
    var choices: [String]
    var answer: Int
    var explanation: String
    var level: Int
    var isArchived: Bool

    init(_ s: GrammarSnapshot) {
        id = s.id
        category = s.category
        question = s.question
        questionJa = s.questionJa
        choices = s.choices
        answer = s.answer
        explanation = s.explanation
        level = s.level
        isArchived = false
    }

    func apply(_ s: GrammarSnapshot) {
        category = s.category
        question = s.question
        questionJa = s.questionJa
        choices = s.choices
        answer = s.answer
        explanation = s.explanation
        level = s.level
        isArchived = false
    }

    var snapshot: GrammarSnapshot {
        GrammarSnapshot(id: id, category: category, question: question, questionJa: questionJa, choices: choices,
                        answer: answer, explanation: explanation, level: level)
    }
}

@Model
final class Word {
    @Attribute(.unique) var id: String
    var word: String
    var pos: String
    var meaning: String
    var example: String
    var exampleJa: String
    /// 例文 3 つ [v1.7]。既定値は軽量マイグレーション用。空なら example / exampleJa の 1 つだけ
    var examples: [ExampleSentence] = []
    var distractors: [String]
    var category: String
    var level: Int
    var isArchived: Bool

    init(_ s: WordSnapshot) {
        id = s.id
        word = s.word
        pos = s.pos
        meaning = s.meaning
        example = s.example
        exampleJa = s.exampleJa
        examples = s.examples
        distractors = s.distractors
        category = s.category
        level = s.level
        isArchived = false
    }

    func apply(_ s: WordSnapshot) {
        word = s.word
        pos = s.pos
        meaning = s.meaning
        example = s.example
        exampleJa = s.exampleJa
        examples = s.examples
        distractors = s.distractors
        category = s.category
        level = s.level
        isArchived = false
    }

    var snapshot: WordSnapshot {
        WordSnapshot(id: id, word: word, pos: pos, meaning: meaning,
                     examples: examples.isEmpty ? [ExampleSentence(en: example, ja: exampleJa)] : examples,
                     distractors: distractors, category: category, level: level)
    }
}

/// 学習履歴。問題の id（itemID）に紐づく独立したレコード。
/// 問題本文を更新・アーカイブしても履歴は残る。
/// **[v1.7]** iCloud 同期の制約（§2.3）: `@Attribute(.unique)` は使えず、全プロパティに既定値が要る。
/// 同じ itemID が 2 件になったら取得時にまとめる（AppModel.mergeDuplicateRecords）
@Model
final class ItemProgress {
    var itemID: String = ""
    var recentResults: [Bool] = []     // 直近3回。古い順
    var totalCorrect: Int = 0
    var totalAnswered: Int = 0
    var isBookmarked: Bool = false
    var lastAnsweredAt: Date?
    /// はじめて習得（直近3回すべて正解）した日時 [v1.4]。一度習得した問題は復習で間違えても次の正解で習得に戻る
    var masteredAt: Date?

    init(itemID: String) {
        self.itemID = itemID
    }

    /// 同期で重複した 2 件を 1 件にまとめる（§2.3）。self を残す側として other を取り込む
    func absorb(_ other: ProgressSnapshot) {
        let merged = RecordMerge.merge(snapshot, other)
        recentResults = merged.recentResults
        totalCorrect = merged.totalCorrect
        totalAnswered = merged.totalAnswered
        isBookmarked = merged.isBookmarked
        lastAnsweredAt = merged.lastAnsweredAt
        masteredAt = merged.masteredAt
    }

    func record(isCorrect: Bool, at date: Date = .now) {
        recentResults.append(isCorrect)
        if recentResults.count > Priority.recentWindow {
            recentResults.removeFirst(recentResults.count - Priority.recentWindow)
        }
        totalAnswered += 1
        if isCorrect { totalCorrect += 1 }
        lastAnsweredAt = date
        if masteredAt == nil, Priority.isGraduated(recentResults) { masteredAt = date }
    }

    var snapshot: ProgressSnapshot {
        ProgressSnapshot(itemID: itemID, recentResults: recentResults, totalCorrect: totalCorrect,
                         totalAnswered: totalAnswered, isBookmarked: isBookmarked,
                         lastAnsweredAt: lastAnsweredAt, masteredAt: masteredAt)
    }
}

/// 1セット（10問）の記録。完走したセットのみ保存する（途中離脱は保存しない）
@Model
final class StudySession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var finishedAt: Date = Date.now
    var mode: String = "auto"   // DrillMode.rawValue。おまかせは "auto"
    var category: String?       // nil = ミックス
    var questionFormat: String? // 単語のとき WordFormat.rawValue。ランダムなら nil
    var results: [SessionResult] = []

    static let autoMode = "auto"

    init(startedAt: Date, finishedAt: Date, mode: DrillMode?, category: String?,
         questionFormat: WordFormat?, results: [SessionResult]) {
        id = UUID()
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.mode = mode?.rawValue ?? Self.autoMode
        self.category = category
        self.questionFormat = questionFormat?.rawValue
        self.results = results
    }
}

nonisolated struct SessionResult: Codable, Hashable, Sendable {
    var itemID: String
    var isCorrect: Bool
    var chosenIndex: Int
    var elapsedMs: Int
}

/// ストアの構成（§2.3 [v1.7]）。
/// - 記録ストア `default.store`（1.0 からのファイルそのまま）: ItemProgress / StudySession。iCloud のプライベートデータベースに同期
/// - 問題ストア `questions.store`: GrammarQuestion / Word。ローカルのみ（同梱 JSON から端末ごとに取り込む）
/// 1.0 では 4 つのモデルが default.store に同居していた。問題の 2 モデルは軽量マイグレーションで default.store から外れ、
/// 新しい questions.store に取り込み直す（AppModel.importBundledDataIfNeeded が fingerprint を消して再取り込みする）
nonisolated enum AgnoriaSchema {
    static let questionModels: [any PersistentModel.Type] = [GrammarQuestion.self, Word.self]
    static let recordModels: [any PersistentModel.Type] = [ItemProgress.self, StudySession.self]
    static let models: [any PersistentModel.Type] = questionModels + recordModels
    static let cloudKitContainer = "iCloud.com.himatsubu.Agnoria"

    struct Result {
        let container: ModelContainer
        /// 記録ストアが iCloud 同期の構成で開けたか（entitlement が無いビルドや `-cloudSync NO` では false）
        let cloudSync: Bool
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try make(inMemory: inMemory, cloudSync: false).container
    }

    static func make(inMemory: Bool = false, cloudSync: Bool) throws -> Result {
        let schema = Schema(models)
        if inMemory {
            // cloudKitDatabase の既定は .automatic で、iCloud の entitlement があるビルド（テストのホストも）では CloudKit の
            // 検証（unique 不可・既定値必須）が走って問題モデルで失敗する。インメモリは必ず .none
            let questions = ModelConfiguration("questions", schema: Schema(questionModels), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let records = ModelConfiguration("records", schema: Schema(recordModels), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return Result(container: try ModelContainer(for: schema, configurations: [questions, records]), cloudSync: false)
        }
        let dir = URL.applicationSupportDirectory
        let questions = ModelConfiguration("questions", schema: Schema(questionModels),
                                           url: dir.appending(path: "questions.store"), cloudKitDatabase: .none)
        let recordsURL = dir.appending(path: "default.store")
        if cloudSync {
            // iCloud の entitlement（CloudKit コンテナ）が無いビルドでは、ここは throw ではなく後で別スレッドで落ちる。
            // 同期を切るのは起動引数 -cloudSync NO かテスト実行時（cloudSyncRequested）で、entitlement は必須
            let records = ModelConfiguration("records", schema: Schema(recordModels), url: recordsURL,
                                             cloudKitDatabase: .private(cloudKitContainer))
            if let container = try? ModelContainer(for: schema, configurations: [questions, records]) {
                return Result(container: container, cloudSync: true)
            }
        }
        let records = ModelConfiguration("records", schema: Schema(recordModels), url: recordsURL, cloudKitDatabase: .none)
        return Result(container: try ModelContainer(for: schema, configurations: [questions, records]), cloudSync: false)
    }

    /// 起動引数 `-cloudSync NO` で同期を切る（UI テストとシミュレータ作業用。利用者向けの設定ではない）。
    /// ユニットテストのホストとして起動したときも切る（テストが iCloud に触れないため）
    static func cloudSyncRequested(defaults: UserDefaults = .standard,
                                   environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestSessionIdentifier"] != nil { return false }
        return defaults.object(forKey: "cloudSync") == nil ? true : defaults.bool(forKey: "cloudSync")
    }
}
