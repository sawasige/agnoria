import SwiftUI

/// 全画面の背景。Liquid Glass が屈折させるための淡いメッシュグラデーション（§7 [v1.2]）
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.55, 0.45], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: colorScheme == .dark ? Self.darkColors : Self.lightColors
        )
        .ignoresSafeArea()
    }

    // アクセント（くすんだ青紫）系で、ライトは白寄り、ダークは黒寄りに
    private static let lightColors: [Color] = [
        Color(red: 0.93, green: 0.93, blue: 0.99), Color(red: 0.88, green: 0.91, blue: 1.00), Color(red: 0.96, green: 0.95, blue: 0.99),
        Color(red: 0.90, green: 0.89, blue: 0.98), Color(red: 0.97, green: 0.97, blue: 1.00), Color(red: 0.86, green: 0.90, blue: 0.99),
        Color(red: 0.94, green: 0.92, blue: 0.99), Color(red: 0.89, green: 0.93, blue: 1.00), Color(red: 0.95, green: 0.95, blue: 1.00),
    ]
    private static let darkColors: [Color] = [
        Color(red: 0.07, green: 0.07, blue: 0.13), Color(red: 0.09, green: 0.11, blue: 0.20), Color(red: 0.06, green: 0.06, blue: 0.11),
        Color(red: 0.11, green: 0.09, blue: 0.19), Color(red: 0.08, green: 0.09, blue: 0.16), Color(red: 0.10, green: 0.12, blue: 0.22),
        Color(red: 0.05, green: 0.05, blue: 0.10), Color(red: 0.09, green: 0.08, blue: 0.16), Color(red: 0.07, green: 0.08, blue: 0.14),
    ]
}
