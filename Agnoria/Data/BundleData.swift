import Foundation
import CryptoKit

/// バンドル JSON の読み込みと検証
nonisolated enum BundleData {
    struct Payload: Sendable {
        var words: [WordSnapshot]
        var grammar: [GrammarSnapshot]
        /// 両ファイルの内容ハッシュ。変化がなければ取り込みをスキップする
        var fingerprint: String
    }

    enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        var description: String {
            switch self { case .missing(let n): "バンドルに \(n) がありません" }
        }
    }

    static func load(bundle: Bundle = .main) throws -> Payload {
        guard let wordsURL = bundle.url(forResource: "words", withExtension: "json") else {
            throw LoadError.missing("words.json")
        }
        guard let grammarURL = bundle.url(forResource: "grammar", withExtension: "json") else {
            throw LoadError.missing("grammar.json")
        }
        let wordsData = try Data(contentsOf: wordsURL)
        let grammarData = try Data(contentsOf: grammarURL)
        return try decode(wordsData: wordsData, grammarData: grammarData)
    }

    static func decode(wordsData: Data, grammarData: Data) throws -> Payload {
        let decoder = JSONDecoder()
        let words = try decoder.decode([WordSnapshot].self, from: wordsData)
        let grammar = try decoder.decode([GrammarSnapshot].self, from: grammarData)
        var hasher = SHA256()
        hasher.update(data: wordsData)
        hasher.update(data: grammarData)
        let fp = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return Payload(words: words, grammar: grammar, fingerprint: fp)
    }

    /// データ品質チェック（§8）。問題があれば説明文を返す
    static func validate(_ p: Payload) -> [String] {
        var issues: [String] = []
        var ids = Set<String>()
        for w in p.words {
            if !ids.insert(w.id).inserted { issues.append("重複 id: \(w.id)") }
            if w.distractors.count != 3 { issues.append("\(w.id): distractors は3つ必要") }
            if w.distractors.contains(w.meaning) { issues.append("\(w.id): distractors に正解が含まれる") }
            if Set(w.distractors).count != w.distractors.count { issues.append("\(w.id): distractors が重複") }
            if WordCategory(rawValue: w.category) == nil { issues.append("\(w.id): 未知の category \(w.category)") }
            if Level(rawValue: w.level) == nil { issues.append("\(w.id): level が 450/500/550/600 以外") }
        }
        for g in p.grammar {
            if !ids.insert(g.id).inserted { issues.append("重複 id: \(g.id)") }
            if g.choices.count != 4 { issues.append("\(g.id): choices は4つ必要") }
            if Set(g.choices).count != g.choices.count { issues.append("\(g.id): choices が重複") }
            if !(0..<g.choices.count).contains(g.answer) { issues.append("\(g.id): answer が範囲外") }
            if !g.question.contains(Cloze.blank) { issues.append("\(g.id): 問題文に空欄 ______ がない") }
            if g.questionJa.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("\(g.id): question_ja が空") }
            if g.questionJa.contains(Cloze.blank) { issues.append("\(g.id): question_ja に空欄が残っている") }
            if GrammarCategory(rawValue: g.category) == nil { issues.append("\(g.id): 未知の category \(g.category)") }
            if Level(rawValue: g.level) == nil { issues.append("\(g.id): level が 450/500/550/600 以外") }
        }
        return issues
    }
}
