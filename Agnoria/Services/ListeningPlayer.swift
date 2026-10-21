import AVFoundation
import Observation

/// リスニング（応答問題）の音声（§4.2 / §6 [v1.9]）。台本（ListeningScript: 番号 → 問いかけ → 記号と応答 3 つ）を合成音声で順に読む。
/// 今読んでいる部分（番号 / 問いかけ / 応答の番号）を公開し、画面はそれで再生中の応答を光らせる。
/// 再生は意図した操作なので、iOS ではマナーモードでも鳴る `.playback` にし、終わったら `.ambient` に戻す
@MainActor
@Observable
final class ListeningPlayer: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = ListeningPlayer()

    typealias Part = ListeningPart


    /// 今読んでいる部分。読んでいなければ nil
    private(set) var playing: Part?
    /// 再生中の問題
    private(set) var questionID: UUID?

    private let synthesizer = AVSpeechSynthesizer()
    private var parts: [ObjectIdentifier: Part] = [:]
    private var lastUtterance: ObjectIdentifier?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 起動引数 `-speech NO` とユニットテストのホストでは鳴らさない（UI テストは launchQuiet がこれで起動）
    static var isAvailable: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil { return false }
        return UserDefaults.standard.object(forKey: "speech") == nil || UserDefaults.standard.bool(forKey: "speech")
    }

    /// 問いかけと応答を最初から読む。読んでいる途中なら止めて読み直す。number はセット内の番号（1 から）
    func play(_ q: QuizQuestion, number: Int, rate: Double) {
        cancel()
        guard Self.isAvailable else { return }
        questionID = q.id
        let pick = ListeningVoice.pick(seed: q.itemID, available: Self.availableVoices())
        let qVoice = pick.flatMap { AVSpeechSynthesisVoice(identifier: $0.question) } ?? AVSpeechSynthesisVoice(language: "en-US")
        let rVoice = pick.flatMap { AVSpeechSynthesisVoice(identifier: $0.responses) } ?? qVoice
        // ナレーター（番号・記号）と問いかけは同じ声、応答は別の声
        let utterances: [(AVSpeechUtterance, Part)] = ListeningScript.make(number: number, question: q.prompt, choices: q.choices).map { s in
            let u = AVSpeechUtterance(string: s.text)
            u.voice = (s.role == .speaker && s.part != .question) ? rVoice : qVoice
            u.rate = Float(rate)
            u.postUtteranceDelay = s.pauseAfter
            return (u, s.part)
        }

        parts = Dictionary(uniqueKeysWithValues: utterances.map { (ObjectIdentifier($0.0), $0.1) })
        lastUtterance = utterances.last.map { ObjectIdentifier($0.0) }
        Task {
            await AudioSession.set(.playback)
            for (u, _) in utterances { synthesizer.speak(u) }
        }
    }

    func stop() {
        cancel()
        Task { await AudioSession.restoreAmbient() }
    }

    /// 読み上げを止めて状態を消す（音声セッションは触らない。読み直すときは .playback のまま）
    private func cancel() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        parts = [:]
        lastUtterance = nil
        playing = nil
        questionID = nil
    }

    /// 最後まで読み終えた
    private func finish() {
        cancel()
        Task { await AudioSession.restoreAmbient() }
    }


    /// 端末にある英語の声
    static func availableVoices() -> [ListeningVoice.Candidate] {
        AVSpeechSynthesisVoice.speechVoices().map {
            ListeningVoice.Candidate(identifier: $0.identifier, language: $0.language,
                                     quality: $0.quality.rawValue, gender: $0.gender.rawValue)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate（呼ばれるスレッドは保証されないので MainActor に移す）

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            if let part = self.parts[id] { self.playing = part }
        }
    }

    /// 読み終えても `playing` は消さず、次の読み上げが始まるまで今の部分を保つ（記号「A.」と応答の文の間の 0.25 秒で
    /// 記号が消えて点き直すチラつきを避ける。SPEC-REVIEW N8）。最後の読み上げを終えたときだけ消す
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.parts[id] != nil, id == self.lastUtterance else { return }
            self.finish()
        }
    }


    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            if self.parts[id] != nil { self.finish() }
        }
    }
}
