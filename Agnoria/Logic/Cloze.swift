import Foundation

/// 例文中の単語を空欄に置き換える（§3.1）
nonisolated enum Cloze {
    static let blank = "______"

    /// 置換できなければ nil（その語は cloze 対象外）
    static func fill(_ example: String, word: String) -> String? {
        let target = word.lowercased()
        guard !target.isEmpty else { return nil }

        // 複数語（句）は大文字小文字を無視して部分一致
        if target.contains(" ") {
            guard let range = example.range(of: target, options: [.caseInsensitive]) else { return nil }
            return example.replacingCharacters(in: range, with: blank)
        }

        let tokens = tokenRanges(in: example)
        // 1. 完全一致を優先
        if let r = tokens.first(where: { example[$0].lowercased() == target }) {
            return example.replacingCharacters(in: r, with: blank)
        }
        // 2. 活用形（語尾変化）一致
        if let r = tokens.first(where: { matchesInflection(token: example[$0].lowercased(), word: target) }) {
            return example.replacingCharacters(in: r, with: blank)
        }
        return nil
    }

    /// 例文中の語 `token`（大文字小文字も含めて完全一致する 1 語）を空欄にする [v2.2]。無ければ nil
    static func blankOut(_ example: String, token: String) -> String? {
        guard !token.isEmpty, let r = tokenRanges(in: example).first(where: { example[$0] == token }) else { return nil }
        return example.replacingCharacters(in: r, with: blank)
    }

    /// 単純な先頭一致ではなく、英語の規則的な語尾変化だけを許可する
    /// （"in" が "invoice" に化けるような誤置換を防ぐ）
    static func matchesInflection(token: String, word: String) -> Bool {
        guard token != word, word.count >= 3 else { return false }
        let suffixes = ["s", "es", "ed", "d", "ing", "ly", "er", "est", "ment", "ion", "tion", "al"]
        if token.hasPrefix(word), suffixes.contains(String(token.dropFirst(word.count))) {
            return true
        }
        // -e 脱落: estimate → estimating, arrange → arranging
        if word.hasSuffix("e") {
            let stem = String(word.dropLast())
            if token == stem + "ing" || token == stem + "ation" { return true }
        }
        // -y → -ies / -ied / -ier: apply → applies, applied
        if word.hasSuffix("y") {
            let stem = String(word.dropLast())
            if ["ies", "ied", "ier", "iest"].contains(where: { token == stem + $0 }) { return true }
        }
        // 子音重ね: ship → shipping, plan → planned
        if let last = word.last {
            let doubled = word + String(last)
            if token == doubled + "ing" || token == doubled + "ed" || token == doubled + "er" { return true }
        }
        return false
    }

    private static func tokenRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index? = nil
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            let isWordChar = c.isLetter || c == "'" || c == "-" || c == "’"
            if isWordChar {
                if start == nil { start = i }
            } else if let s = start {
                ranges.append(s..<i)
                start = nil
            }
            i = text.index(after: i)
        }
        if let s = start { ranges.append(s..<text.endIndex) }
        return ranges
    }
}
