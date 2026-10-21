import Foundation

/// 同梱の問題データをメモリに持つ（§2.1 [v1.9]、Issue #21）。起動時に JSON を読み、以後は値型のまま参照する。
/// SwiftData には入れない: DB が要るのは iCloud で同期する学習記録（ItemProgress / StudySession）だけで、
/// 問題データは読み取り専用の数百 KB。JSON に無い id の記録は出題と集計から自然に外れる（記録自体は消さない）
nonisolated struct QuestionCatalog: Sendable {
    let words: [WordSnapshot]
    let grammar: [GrammarSnapshot]
    let listening: [ListeningSnapshot]
    let wordByID: [String: WordSnapshot]
    let grammarByID: [String: GrammarSnapshot]
    let listeningByID: [String: ListeningSnapshot]

    init(words: [WordSnapshot], grammar: [GrammarSnapshot], listening: [ListeningSnapshot]) {
        self.words = words
        self.grammar = grammar
        self.listening = listening
        wordByID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        grammarByID = Dictionary(grammar.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        listeningByID = Dictionary(listening.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    init(_ payload: BundleData.Payload) {
        self.init(words: payload.words, grammar: payload.grammar, listening: payload.listening)
    }

    static let empty = QuestionCatalog(words: [], grammar: [], listening: [])

    var isEmpty: Bool { words.isEmpty && grammar.isEmpty && listening.isEmpty }

    /// 軸の全問題（id・分野・レベル）
    func items(_ mode: DrillMode) -> [(id: String, category: String, level: Int)] {
        switch mode {
        case .word: words.map { ($0.id, $0.category, $0.level) }
        case .grammar: grammar.map { ($0.id, $0.category, $0.level) }
        case .listening: listening.map { ($0.id, $0.category, $0.level) }
        }
    }

    /// 帯の集計用（id・レベル）
    func levelItems(_ mode: DrillMode) -> [(id: String, level: Int)] {
        items(mode).map { ($0.id, $0.level) }
    }

    /// 出題対象のレベルに絞った（id・分野）。ホーム・分野・進捗の集計用
    func categoryItems(_ mode: DrillMode, levels: Set<Int>) -> [(id: String, category: String)] {
        items(mode).filter { levels.contains($0.level) }.map { ($0.id, $0.category) }
    }

    /// 軸ごとの帯の集計用
    var levelItemsByMode: [DrillMode: [(id: String, level: Int)]] {
        Dictionary(uniqueKeysWithValues: DrillMode.allCases.map { ($0, levelItems($0)) })
    }
}
