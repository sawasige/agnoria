import AVFoundation

/// 読み上げと効果音で共有する AVAudioSession の設定（§6）。iOS のみ。
/// マナーモード（サイレントスイッチ）に従う .ambient カテゴリ。
/// setCategory / setActive は同期的にメインスレッドを止めうる（Xcode の AVAudioSession Hang Risk 診断）ので、
/// actor に閉じ込めてメインスレッド以外で実行する
enum AudioSession {
    static func activateIfNeeded() async {
        await Worker.shared.activateIfNeeded()
    }

    private actor Worker {
        static let shared = Worker()
        private var configured = false

        func activateIfNeeded() {
            #if os(iOS)
            guard !configured else { return }
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.ambient, mode: .spokenAudio, options: [.duckOthers])
                try session.setActive(true)
                configured = true
            } catch {
                // 失敗しても音が出ないだけ。次回また試す
            }
            #endif
        }
    }
}
