import AVFoundation

/// 読み上げと効果音で共有する AVAudioSession の設定（§6）。iOS のみ。
/// ふだんはマナーモード（サイレントスイッチ）に従う .ambient カテゴリ。
/// **[v1.9]** リスニングの再生中だけ、意図した操作なのでマナーモードでも鳴る .playback にし、終わったら .ambient に戻す。
/// setCategory / setActive は同期的にメインスレッドを止めうる（Xcode の AVAudioSession Hang Risk 診断）ので、
/// actor に閉じ込めてメインスレッド以外で実行する
nonisolated enum AudioSession {
    enum Category: Sendable { case ambient, playback }


    /// 効果音と例文の読み上げの前に呼ぶ。まだ設定していなければ .ambient にする（リスニング再生中の .playback は変えない）
    static func activateIfNeeded() async {
        await Worker.shared.activateIfNeeded()
    }

    static func set(_ category: Category) async {
        await Worker.shared.set(category)
    }

    /// リスニングの再生が終わったら .ambient に戻す
    static func restoreAmbient() async {
        await Worker.shared.restoreAmbient()
    }

    private actor Worker {
        static let shared = Worker()
        private var current: Category?

        func activateIfNeeded() {
            if current == nil { set(.ambient) }
        }

        func restoreAmbient() {
            if current == .playback { set(.ambient) }
        }

        func set(_ category: Category) {
            #if os(iOS)
            guard current != category else { return }
            let session = AVAudioSession.sharedInstance()
            do {
                switch category {
                case .ambient: try session.setCategory(.ambient, mode: .spokenAudio, options: [.duckOthers])
                case .playback: try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                }
                try session.setActive(true)
                current = category
            } catch {
                // 失敗しても音が出ないだけ。次回また試す
            }
            #else
            current = category
            #endif
        }
    }
}
