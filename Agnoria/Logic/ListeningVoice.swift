import Foundation

/// リスニングの声の選び方（§6 [v1.9]）。純粋関数。
/// 問いかけと応答で別の声にし、発音（en-US / en-GB / en-AU）を問題ごとに変える。端末にある声から品質の高いものを選ぶ
nonisolated enum ListeningVoice {
    /// 混ぜる発音。端末にその言語の声が無ければ en-US に落ちる
    static let languages = ["en-US", "en-GB", "en-AU"]

    /// 端末の声 1 つ（AVSpeechSynthesisVoice の写し。テストで差し替えるため）
    struct Candidate: Hashable, Sendable {
        var identifier: String
        var language: String
        /// AVSpeechSynthesisVoiceQuality の rawValue（default 1 / enhanced 2 / premium 3）
        var quality: Int
        /// AVSpeechSynthesisVoiceGender の rawValue（unspecified 0 / male 1 / female 2）
        var gender: Int
    }

    struct Pick: Equatable, Sendable {
        var question: String
        var responses: String
    }

    /// 聞き取りの練習に使える声か。ふつうの声（`com.apple.voice.`: compact / enhanced / premium）と Siri の声だけにし、
    /// 機械的な Eloquence（Eddy / Grandma / Rocko など。iPhone にも入っている）と Mac の旧声・遊び声
    /// （`com.apple.speech.synthesis.voice.`: Zarvox / Bells / Whisper など）は除く。どれも品質は default で見分けがつかない
    static func isNatural(_ v: Candidate) -> Bool {
        let id = v.identifier
        if id.hasPrefix("com.apple.eloquence.") || id.hasPrefix("com.apple.speech.synthesis.voice.") { return false }
        return id.hasPrefix("com.apple.voice.") || id.contains("siri")
    }

    /// 問題の id から決定的に 2 つの声を選ぶ（同じ問題は毎回同じ声）。
    /// 問いかけの言語は id のハッシュで選び、応答はできるだけ別の声（別の性別 → 別の言語の順で探す）。
    /// 候補はふつうの声だけ（`isNatural`）。1 つも無ければ全部から選ぶ
    static func pick(seed: String, available all: [Candidate]) -> Pick? {
        let natural = all.filter(isNatural)
        let available = natural.isEmpty ? all : natural
        guard !available.isEmpty else { return nil }

        let h = hash(seed)
        let langs = languages.filter { lang in available.contains { $0.language == lang } }
        guard !langs.isEmpty else {
            let any = best(available, salt: h)
            return Pick(question: any.identifier, responses: any.identifier)
        }
        let qLang = langs[Int(h % UInt64(langs.count))]
        let question = best(available.filter { $0.language == qLang }, salt: h)
        // 応答: 同じ言語で別の性別の声 → 別の言語の声 → 同じ声
        let otherGender = available.filter { $0.language == qLang && $0.gender != question.gender && $0.identifier != question.identifier }
        let otherLang = available.filter { $0.language != qLang && languages.contains($0.language) }
        let pool = !otherGender.isEmpty ? otherGender : (!otherLang.isEmpty ? otherLang : [question])
        let responses = best(pool, salt: h &+ 1)
        return Pick(question: question.identifier, responses: responses.identifier)
    }

    /// 品質が最も高いもの。同じ品質が複数あれば salt で 1 つ選ぶ
    private static func best(_ voices: [Candidate], salt: UInt64) -> Candidate {
        let top = voices.map(\.quality).max() ?? 0
        let tier = voices.filter { $0.quality == top }.sorted { $0.identifier < $1.identifier }
        return tier[Int(salt % UInt64(tier.count))]
    }

    /// 端末やプロセスによらず同じ値になるハッシュ（FNV-1a）
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return h
    }
}
