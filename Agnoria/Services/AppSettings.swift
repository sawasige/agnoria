import Foundation
import Observation

/// 設定（§4.4）。UserDefaults に保存
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let levels = "enabledLevels"
        static let speechRate = "speechRate"
        static let importedFingerprint = "importedDataFingerprint"
    }

    private let defaults: UserDefaults

    var enabledLevels: Set<Int> {
        didSet { defaults.set(enabledLevels.sorted(), forKey: Key.levels) }
    }

    /// AVSpeechUtterance.rate（0.0〜1.0）。デフォルトはやや遅め
    var speechRate: Double {
        didSet { defaults.set(speechRate, forKey: Key.speechRate) }
    }

    var importedFingerprint: String? {
        get { defaults.string(forKey: Key.importedFingerprint) }
        set { defaults.set(newValue, forKey: Key.importedFingerprint) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.array(forKey: Key.levels) as? [Int], !saved.isEmpty {
            enabledLevels = Set(saved)
        } else {
            enabledLevels = Level.allValues
        }
        let rate = defaults.double(forKey: Key.speechRate)
        speechRate = rate == 0 ? 0.45 : rate
    }

    static let speechRateRange: ClosedRange<Double> = 0.3...0.6
}
