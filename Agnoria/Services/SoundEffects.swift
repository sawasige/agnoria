import AVFoundation

/// 正解・不正解の効果音（§4.2 [v1.2]）。音源は Resources/Sounds の短い CAF。
/// AVAudioPlayer の prepareToPlay / play は内部で同期の setActive を呼びメインスレッドを止めうるので、
/// プレイヤーの生成と再生は actor の中（メインスレッド以外）で行う
actor SoundEffects {
    enum Effect: String, CaseIterable, Sendable {
        case correct
        case wrong
    }

    static let shared = SoundEffects()

    private var players: [Effect: AVAudioPlayer] = [:]
    private var loaded = false

    private init() {}

    /// 呼び出し側（MainActor の View）を待たせない。失敗は無視する
    nonisolated func play(_ effect: Effect) {
        Task { await playNow(effect) }
    }

    private func playNow(_ effect: Effect) async {
        await AudioSession.activateIfNeeded()
        loadIfNeeded()
        guard let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "caf"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[effect] = player
        }
    }
}
