import Foundation
import Observation

/// 設定（§4.4）。UserDefaults に保存
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let unlockedLevel = "unlockedLevel"
        static let speechRate = "speechRate"
        static let autoSpeak = "autoSpeak"
        static let soundEffects = "soundEffects"
        static let swipeHintDone = "swipeHintDone"
        static let importedFingerprint = "importedDataFingerprint"
    }

    private let defaults: UserDefaults

    /// 到達しているスコア帯（§3.4）。450 から始まり、習得率 80% で次へ進む。手動でも変えられる
    var unlockedLevel: Int {
        didSet { defaults.set(unlockedLevel, forKey: Key.unlockedLevel) }
    }

    /// 出題対象のレベル = 到達帯まで
    var enabledLevels: Set<Int> { Stage.unlockedLevels(upTo: unlockedLevel) }

    /// AVSpeechUtterance.rate（0.0〜1.0）。デフォルトはやや遅め
    var speechRate: Double {
        didSet { defaults.set(speechRate, forKey: Key.speechRate) }
    }

    /// 回答後に例文を自動で読み上げる。デフォルト ON
    var autoSpeak: Bool {
        didSet { defaults.set(autoSpeak, forKey: Key.autoSpeak) }
    }

    /// 正解・不正解の効果音。デフォルト ON
    var soundEffects: Bool {
        didSet { defaults.set(soundEffects, forKey: Key.soundEffects) }
    }

    /// 回答後の「左にスワイプでも次へ」のヒントを消したか（一度スワイプで進んだら true）[v1.4]
    var swipeHintDone: Bool {
        didSet { defaults.set(swipeHintDone, forKey: Key.swipeHintDone) }
    }

    var importedFingerprint: String? {
        get { defaults.string(forKey: Key.importedFingerprint) }
        set { defaults.set(newValue, forKey: Key.importedFingerprint) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.integer(forKey: Key.unlockedLevel)
        unlockedLevel = Stage.levels.contains(saved) ? saved : Stage.first
        let rate = defaults.double(forKey: Key.speechRate)
        speechRate = rate == 0 ? 0.45 : rate
        // bool(forKey:) は起動引数（-soundEffects NO など）の文字列も真偽に解釈する。UI テストは引数で音を切る
        autoSpeak = defaults.object(forKey: Key.autoSpeak) == nil ? true : defaults.bool(forKey: Key.autoSpeak)
        soundEffects = defaults.object(forKey: Key.soundEffects) == nil ? true : defaults.bool(forKey: Key.soundEffects)
        swipeHintDone = defaults.bool(forKey: Key.swipeHintDone)
    }

    static let speechRateRange: ClosedRange<Double> = 0.3...0.6

    /// 効果音が鳴り終わってから読み上げを始めるまでの間
    var autoSpeakDelay: Duration { .milliseconds(soundEffects ? 700 : 150) }
}
