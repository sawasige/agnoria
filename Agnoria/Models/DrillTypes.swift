import Foundation

/// 出題モード（単語 / 文法）
nonisolated enum DrillMode: String, CaseIterable, Codable, Hashable, Sendable {
    case word
    case grammar

    var title: String {
        switch self {
        case .word: "単語"
        case .grammar: "文法"
        }
    }

    var categories: [String] {
        switch self {
        case .word: WordCategory.allCases.map(\.rawValue)
        case .grammar: GrammarCategory.allCases.map(\.rawValue)
        }
    }
}

/// 単語の出題形式
nonisolated enum WordFormat: String, CaseIterable, Codable, Hashable, Sendable {
    case meaning
    case cloze
    case jaToEn

    var title: String {
        switch self {
        case .meaning: "意味"
        case .cloze: "穴埋め"
        case .jaToEn: "日→英"
        }
    }
}

nonisolated enum GrammarCategory: String, CaseIterable, Sendable {
    case partOfSpeech = "品詞"
    case prepositionConjunction = "前置詞・接続詞"
    case vocabulary = "語彙"
    case tenseVoice = "時制・態"
    case pronounRelative = "代名詞・関係詞"
}

nonisolated enum WordCategory: String, CaseIterable, Sendable {
    case business = "ビジネス一般"
    case hr = "人事・採用"
    case meeting = "会議・連絡"
    case store = "店舗・顧客"
    case confusable = "混同しやすい語"
}

nonisolated enum Level: Int, CaseIterable, Sendable {
    case l450 = 450
    case l500 = 500
    case l550 = 550
    case l600 = 600

    static let allValues: Set<Int> = Set(allCases.map(\.rawValue))
}

/// 出題対象の絞り込み
nonisolated enum DrillFilter: Hashable, Sendable {
    case all
    case wrongOnly      // 直近3回に不正解を含むもの
    case bookmarked     // ブックマーク済み
}

/// 1セットの条件
nonisolated struct QuizConfig: Hashable, Sendable {
    var mode: DrillMode
    var category: String?           // nil = ミックス
    var format: WordFormat?         // 単語のみ。nil = ランダム
    var filter: DrillFilter = .all
    /// 結果画面「間違えた問題だけやり直す」用。指定時はこの id のみ対象
    var restrictTo: Set<String>? = nil

    var categoryTitle: String { category ?? "ミックス" }
}
