import SwiftUI

/// 進捗画面（§4.6 [v1.2]）。本実装は後続ステップで差し替える
struct StatsView: View {
    var body: some View {
        ContentUnavailableView("進捗", systemImage: "chart.bar")
            .navigationTitle("進捗")
    }
}
