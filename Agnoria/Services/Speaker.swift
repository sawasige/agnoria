import AVFoundation

/// 例文の読み上げ（§6）。en-US 固定
@MainActor
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var sessionConfigured = false

    private init() {}

    func speak(_ text: String, rate: Double) {
        Task {
            await activateSessionIfNeeded()
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

    /// サイレントモードでも鳴らす。AVAudioSession は iOS のみ。
    /// 同期の setActive はメインスレッドを止めうるので、iOS 27 の非同期 API を使う
    private func activateSessionIfNeeded() async {
        #if os(iOS)
        guard !sessionConfigured else { return }
        sessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        _ = try? await session.activate(options: [])
        #endif
    }
}
