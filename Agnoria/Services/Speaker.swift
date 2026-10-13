import AVFoundation

/// 例文の読み上げ（§6）。en-US 固定
@MainActor
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String, rate: Double) {
        Task {
            await AudioSession.activateIfNeeded()
            if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = Float(rate)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
