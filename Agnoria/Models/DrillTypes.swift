import Foundation

/// 出題モード（単語 / 文法 / リスニング [v1.9]）。スコア帯の軸でもある（§3.4）
nonisolated enum DrillMode: String, CaseIterable, Codable, Hashable, Sendable {
    case word
    case grammar
    /// Part 2 形式の応答問題（§3.5 [v1.9]）。音声だけで出すので、おまかせ（mode = nil）には混ぜない
    case listening

    var title: String {
        switch self {
        case .word: "単語"
        case .grammar: "文法"
        case .listening: "リスニング"
        }
    }

    var categories: [String] {
        switch self {
        case .word: WordCategory.allCases.map(\.rawValue)
        case .grammar: GrammarCategory.allCases.map(\.rawValue)
        case .listening: ListeningCategory.allCases.map(\.rawValue)
        }
    }

    /// おまかせ（mode = nil）と復習の絞り込みで混ぜる軸の基本。リスニングは音が出せない場面があるので、
    /// ホームの切り替え（`AppSettings.autoIncludesListening`）がオンのときだけ足す
    static let autoModes: [DrillMode] = [.word, .grammar]

    static func autoModes(includingListening: Bool) -> [DrillMode] {
        includingListening ? allCases : autoModes
    }


    /// 分野タイル用の SF Symbols 名。ミックスなど不明な分野は square.grid.2x2
    static func symbol(for category: String) -> String {
        if let g = GrammarCategory(rawValue: category) { return g.symbolName }
        if let w = WordCategory(rawValue: category) { return w.symbolName }
        if let l = ListeningCategory(rawValue: category) { return l.symbolName }
        return "square.grid.2x2"
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

    var symbolName: String {
        switch self {
        case .partOfSpeech: "textformat"
        case .prepositionConjunction: "link"
        case .vocabulary: "character.book.closed"
        case .tenseVoice: "clock"
        case .pronounRelative: "person.2"
        }
    }
}

nonisolated enum WordCategory: String, CaseIterable, Sendable {
    case business = "ビジネス一般"
    case hr = "人事・採用"
    case meeting = "会議・連絡"
    case store = "店舗・顧客"
    case confusable = "混同しやすい語"

    var symbolName: String {
        switch self {
        case .business: "briefcase"
        case .hr: "person.badge.plus"
        case .meeting: "bubble.left.and.bubble.right"
        case .store: "storefront"
        case .confusable: "arrow.left.arrow.right"
        }
    }
}

/// リスニング（応答問題）の問いかけの型 [v1.9]
nonisolated enum ListeningCategory: String, CaseIterable, Sendable {
    case wh = "WH 疑問文"
    case yesNo = "Yes・No 疑問文"
    case request = "依頼・提案"
    case statement = "平叙文"
    case alternativeTag = "選択・付加疑問文"

    var symbolName: String {
        switch self {
        case .wh: "questionmark.bubble"
        case .yesNo: "checkmark.bubble"
        case .request: "hand.raised"
        case .statement: "text.bubble"
        case .alternativeTag: "arrow.triangle.branch"
        }
    }
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
    var mode: DrillMode?            // nil = おまかせ（単語・文法の全分野、§3.2 [v1.2]。リスニングは含まない [v1.9]）

    var category: String?           // nil = ミックス
    var format: WordFormat?         // 単語のみ。nil = ランダム
    var filter: DrillFilter = .all
    /// 結果画面「間違えた問題だけやり直す」用。指定時はこの id のみ対象
    var restrictTo: Set<String>? = nil

    /// おまかせ: 単語・文法をまたいで優先度順に抽出。形式は1問ごとにランダム
    static let auto = QuizConfig(mode: nil, category: nil, format: nil)

    var isAuto: Bool { mode == nil }

    var categoryTitle: String {
        guard mode != nil else { return "おまかせ" }
        return category ?? "ミックス"
    }
}
