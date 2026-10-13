import Testing
import SwiftUI
@testable import Agnoria

@Suite("女神の表情")
struct AgenoriaImageTests {
    @Test("結果の閾値はメッセージと同じ") func mapping() {
        #expect(AgenoriaExpression.forScore(correct: 10, total: 10) == .joy)
        #expect(AgenoriaExpression.forScore(correct: 8, total: 10) == .happy)
        #expect(AgenoriaExpression.forScore(correct: 9, total: 10) == .happy)
        #expect(AgenoriaExpression.forScore(correct: 5, total: 10) == .neutral)
        #expect(AgenoriaExpression.forScore(correct: 4, total: 10) == .sad)
        #expect(AgenoriaExpression.forScore(correct: 0, total: 0) == .neutral)
    }

    @Test("画像がアセットカタログにある") func assetsExist() {
        for e in AgenoriaExpression.allCases {
            #expect(imageExists(e.imageName), "\(e.imageName)")
        }
        #expect(imageExists("AgenoriaPortrait"))
    }

    private func imageExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name, in: Bundle(for: AppModel.self), with: nil) != nil
        #else
        return Bundle(for: AppModel.self).image(forResource: name) != nil
        #endif
    }
}
