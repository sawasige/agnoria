import Foundation
import Observation

/// 設定（§4.4）。UserDefaults に保存
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        /// [v1.8] 軸ごと: unlockedLevel.word / unlockedLevel.grammar。1.2 までの "unlockedLevel"（合算）は移行で消す
        static func unlockedLevel(_ mode: DrillMode) -> String { "unlockedLevel.\(mode.rawValue)" }
        static let legacyUnlockedLevel = "unlockedLevel"
        static let speechRate = "speechRate"
        static let autoSpeak = "autoSpeak"
        static let soundEffects = "soundEffects"
        static let swipeHintDone = "swipeHintDone"
        static func topStageCelebrated(_ mode: DrillMode) -> String { "topStageCelebrated.\(mode.rawValue)" }
        static let legacyTopStageCelebrated = "topStageCelebrated"
        static let stageTracksMigrated = "stageTracksMigrated"
        static let importedFingerprint = "importedDataFingerprint"
        static let storesSplit = "storesSplit"
        static let reviewRequestedVersion = "reviewRequestedVersion"
    }

    private let defaults: UserDefaults

    /// 軸ごとの到達しているスコア帯（§3.4 [v1.8]）。450 から始まり、その軸の帯の習得率 80% で次へ進む。手動でも変えられる
    private(set) var unlockedLevels: [DrillMode: Int]

    func unlockedLevel(_ mode: DrillMode) -> Int { unlockedLevels[mode] ?? Stage.first }

    func setUnlockedLevel(_ level: Int, for mode: DrillMode) {
        unlockedLevels[mode] = level
        defaults.set(level, forKey: Key.unlockedLevel(mode))
    }

    /// 出題対象のレベル = その軸の到達帯まで
    func enabledLevels(_ mode: DrillMode) -> Set<Int> { Stage.unlockedLevels(upTo: unlockedLevel(mode)) }

    /// SetBuilder に渡す形
    var enabledLevelsByMode: [DrillMode: Set<Int>] {
        Dictionary(uniqueKeysWithValues: DrillMode.allCases.map { ($0, enabledLevels($0)) })
    }

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

    /// 最上位の帯（600）のクリアを祝った軸。開く先が無いので軸ごとに 1 回だけ祝う（§4.3.1 [v1.5]）。履歴リセットで戻す
    private(set) var topStageCelebrated: Set<DrillMode>

    func setTopStageCelebrated(_ celebrated: Bool, for mode: DrillMode) {
        if celebrated { topStageCelebrated.insert(mode) } else { topStageCelebrated.remove(mode) }
        defaults.set(celebrated, forKey: Key.topStageCelebrated(mode))
    }

    /// 1.8 で到達帯を軸ごとに分けたか。false なら起動時に記録から軸ごとの到達帯を求め直す（§3.4 [v1.8]）
    var stageTracksMigrated: Bool {
        get { defaults.bool(forKey: Key.stageTracksMigrated) }
        set {
            defaults.set(newValue, forKey: Key.stageTracksMigrated)
            if newValue {
                defaults.removeObject(forKey: Key.legacyUnlockedLevel)
                defaults.removeObject(forKey: Key.legacyTopStageCelebrated)
            }
        }
    }

    /// 1.7 でストアを記録用と問題用に分けたか。false なら起動時に問題データを新しいストアへ取り込み直す（§2.3）
    var storesSplit: Bool {
        get { defaults.bool(forKey: Key.storesSplit) }
        set { defaults.set(newValue, forKey: Key.storesSplit) }
    }

    /// 最後に評価ダイアログを頼んだバージョン（§4.8 [v1.8]）。同じバージョンでは 2 回頼まない
    var reviewRequestedVersion: String? {
        get { defaults.string(forKey: Key.reviewRequestedVersion) }
        set { defaults.set(newValue, forKey: Key.reviewRequestedVersion) }
    }

    var importedFingerprint: String? {
        get { defaults.string(forKey: Key.importedFingerprint) }
        set { defaults.set(newValue, forKey: Key.importedFingerprint) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unlockedLevels = Dictionary(uniqueKeysWithValues: DrillMode.allCases.map { mode in
            let saved = defaults.integer(forKey: Key.unlockedLevel(mode))
            return (mode, Stage.levels.contains(saved) ? saved : Stage.first)
        })
        let rate = defaults.double(forKey: Key.speechRate)
        speechRate = rate == 0 ? 0.45 : rate
        // bool(forKey:) は起動引数（-soundEffects NO など）の文字列も真偽に解釈する。UI テストは引数で音を切る
        autoSpeak = defaults.object(forKey: Key.autoSpeak) == nil ? true : defaults.bool(forKey: Key.autoSpeak)
        soundEffects = defaults.object(forKey: Key.soundEffects) == nil ? true : defaults.bool(forKey: Key.soundEffects)
        swipeHintDone = defaults.bool(forKey: Key.swipeHintDone)
        topStageCelebrated = Set(DrillMode.allCases.filter { defaults.bool(forKey: Key.topStageCelebrated($0)) })
    }

    static let speechRateRange: ClosedRange<Double> = 0.3...0.6

    /// 効果音が鳴り終わってから読み上げを始めるまでの間
    var autoSpeakDelay: Duration { .milliseconds(soundEffects ? 700 : 150) }
}
