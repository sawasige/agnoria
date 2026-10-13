import AVFoundation

/// 正解・不正解の効果音（§4.2 [v1.2]）。音源は Resources/Sounds の短い CAF
@MainActor
final class SoundEffects {
    enum Effect: String, CaseIterable {
        case correct
        case wrong
    }

    static let shared = SoundEffects()

    private var players: [Effect: AVAudioPlayer] = [:]

    private init() {
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "caf"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[effect] = player
        }
    }

    func play(_ effect: Effect) {
        Task {
            await AudioSession.activateIfNeeded()
            guard let player = players[effect] else { return }
            player.currentTime = 0
            player.play()
        }
    }
}
