import Foundation
import CryptoKit

/// バンドル JSON の読み込みと検証
nonisolated enum BundleData {
    struct Payload: Sendable {
        var words: [WordSnapshot]
        var grammar: [GrammarSnapshot]
        /// リスニング（応答問題）[v1.9]
        var listening: [ListeningSnapshot]
        /// 3 ファイルの内容ハッシュ。変化がなければ取り込みをスキップする
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
        guard let listeningURL = bundle.url(forResource: "listening", withExtension: "json") else {
            throw LoadError.missing("listening.json")
        }
        let wordsData = try Data(contentsOf: wordsURL)
        let grammarData = try Data(contentsOf: grammarURL)
        let listeningData = try Data(contentsOf: listeningURL)
        return try decode(wordsData: wordsData, grammarData: grammarData, listeningData: listeningData)
    }

    static func decode(wordsData: Data, grammarData: Data, listeningData: Data) throws -> Payload {
        let decoder = JSONDecoder()
        let words = try decoder.decode([WordSnapshot].self, from: wordsData)
        let grammar = try decoder.decode([GrammarSnapshot].self, from: grammarData)
        let listening = try decoder.decode([ListeningSnapshot].self, from: listeningData)
        var hasher = SHA256()
        hasher.update(data: wordsData)
        hasher.update(data: grammarData)
        hasher.update(data: listeningData)
        let fp = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return Payload(words: words, grammar: grammar, listening: listening, fingerprint: fp)
    }

    /// データ品質チェック（§8）。問題があれば説明文を返す
    static func validate(_ p: Payload) -> [String] {
        var issues: [String] = []
        var ids = Set<String>()
        for w in p.words {
            if !ids.insert(w.id).inserted { issues.append("重複 id: \(w.id)") }
            if w.distractors.count != 3 { issues.append("\(w.id): distractors は3つ必要") }
            if w.examples.count != 3 { issues.append("\(w.id): examples は3つ必要（\(w.examples.count)）") }
            for (i, ex) in w.examples.enumerated() {
                if ex.en.trimmingCharacters(in: .whitespaces).isEmpty || ex.ja.trimmingCharacters(in: .whitespaces).isEmpty {
                    issues.append("\(w.id): examples[\(i)] が空")
                } else if Cloze.fill(ex.en, word: w.word) == nil {
                    issues.append("\(w.id): examples[\(i)] に \(w.word) が見つからない（穴埋めにできない）")
                }
            }
            if Set(w.examples.map(\.en)).count != w.examples.count { issues.append("\(w.id): examples が重複") }
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
        for l in p.listening {
            if !ids.insert(l.id).inserted { issues.append("重複 id: \(l.id)") }
            if l.choices.count != 3 { issues.append("\(l.id): choices は3つ必要") }
            if l.choicesJa.count != l.choices.count { issues.append("\(l.id): choices_ja の数が choices と違う") }
            if Set(l.choices).count != l.choices.count { issues.append("\(l.id): choices が重複") }
            if !(0..<l.choices.count).contains(l.answer) { issues.append("\(l.id): answer が範囲外") }
            var texts = [("question", l.question), ("question_ja", l.questionJa), ("explanation", l.explanation)]
            texts += l.choices.enumerated().map { ("choices[\($0.offset)]", $0.element) }
            texts += l.choicesJa.enumerated().map { ("choices_ja[\($0.offset)]", $0.element) }
            for (name, text) in texts where text.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append("\(l.id): \(name) が空")
            }

            if ListeningCategory(rawValue: l.category) == nil { issues.append("\(l.id): 未知の category \(l.category)") }
            if Level(rawValue: l.level) == nil { issues.append("\(l.id): level が 450/500/550/600 以外") }
        }
        return issues

    }
}
