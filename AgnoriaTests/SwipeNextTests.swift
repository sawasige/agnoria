import Foundation
import Testing
@testable import Agnoria

@Suite("左スワイプで次へ")
struct SwipeNextTests {
    @Test("左へ 80pt なら成立") func left() {
        #expect(SwipeNext.triggers(translation: CGSize(width: -80, height: 5), predicted: CGSize(width: -90, height: 5)))
    }

    @Test("右へは成立しない") func right() {
        #expect(!SwipeNext.triggers(translation: CGSize(width: 80, height: 0), predicted: CGSize(width: 200, height: 0)))
    }

    @Test("短くても速いフリックなら成立") func flick() {
        #expect(SwipeNext.triggers(translation: CGSize(width: -30, height: 2), predicted: CGSize(width: -200, height: 2)))
        #expect(!SwipeNext.triggers(translation: CGSize(width: -30, height: 2), predicted: CGSize(width: -100, height: 2)))
    }

    @Test("縦の動きが大きければスクロール扱い") func vertical() {
        #expect(!SwipeNext.triggers(translation: CGSize(width: -70, height: 100), predicted: CGSize(width: -70, height: 150)))
    }
}
