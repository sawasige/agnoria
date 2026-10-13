import AVFoundation

/// 読み上げと効果音で共有する AVAudioSession の設定（§6）。iOS のみ。
/// マナーモード（サイレントスイッチ）に従う .ambient カテゴリ。同期の setActive はメインスレッドを止めうるので非同期 API を使う
@MainActor
enum AudioSession {
    private static var configured = false

    static func activateIfNeeded() async {
        #if os(iOS)
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .spokenAudio, options: [.duckOthers])
        _ = try? await session.activate(options: [])
        #endif
    }
}
