import Foundation

/// 読み上げている部分（ListeningPlayer.playing と台本の両方で使う。MainActor の外でも比べられるように nonisolated）
nonisolated enum ListeningPart: Equatable, Sendable {
    /// 「Number N.」
    case number
    case question
    /// 記号「A.」を読み始めたところから、その応答を読み終えるまで
    case response(Int)
}


/// リスニングの読み上げの台本（§3.5 [v1.9]）。純粋関数。本番の Part 2 の音声に合わせて、
/// 「Number N.」→ 問いかけ → 「A.」→ 応答 1 → 「B.」→ 応答 2 → 「C.」→ 応答 3 の順に、間を挟んで読む。
/// 番号と記号はナレーター、問いかけと応答は話者の声
nonisolated enum ListeningScript {
    enum Role: Equatable, Sendable {
        /// 番号と記号を読む声（問いかけの声を使う）
        case narrator
        /// 問いかけ・応答を読む声
        case speaker
    }

    struct Segment: Equatable, Sendable {
        var text: String
        var role: Role
        var part: ListeningPlayer.Part
        /// 読み終えてから次を読み始めるまでの間（秒）
        var pauseAfter: TimeInterval
    }

    /// 「Number N.」の後
    static let pauseAfterNumber: TimeInterval = 0.6
    /// 問いかけの後
    static let pauseAfterQuestion: TimeInterval = 1.2
    /// 「A.」などの記号の後
    static let pauseAfterLetter: TimeInterval = 0.25
    /// 応答と次の記号の間
    static let pauseBetweenResponses: TimeInterval = 1.0

    /// number はセット内の番号（1 から）
    static func make(number: Int, question: String, choices: [String]) -> [Segment] {
        var out: [Segment] = [
            Segment(text: "Number \(number).", role: .narrator, part: .number, pauseAfter: pauseAfterNumber),
            Segment(text: question, role: .speaker, part: .question, pauseAfter: pauseAfterQuestion),
        ]
        for (i, choice) in choices.enumerated() {
            let letter = i < QuizQuestion.choiceLabels.count ? QuizQuestion.choiceLabels[i] : "\(i + 1)"
            out.append(Segment(text: "\(letter).", role: .narrator, part: .response(i), pauseAfter: pauseAfterLetter))
            out.append(Segment(text: choice, role: .speaker, part: .response(i),
                               pauseAfter: i == choices.count - 1 ? 0 : pauseBetweenResponses))
        }
        return out
    }
}
