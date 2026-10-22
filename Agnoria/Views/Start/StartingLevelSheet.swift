import SwiftUI

/// 初回起動で「今のスコアの目安」を 1 回だけ聞き、開始のスコア帯を合わせる（§4.1 [v2.0]、Issue #50）。
/// 選ぶかあとでにするまで閉じられない。設定の到達帯で後から変えられる
struct StartingLevelSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("今のスコアの目安は？")
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                    Text("合ったスコア帯から始めます。あとから設定で変えられます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 10) {
                        ForEach(AppModel.StartingLevelChoice.allCases) { choice in
                            Button {
                                choose(choice)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.title)
                                        .font(.headline)
                                    Text(choice.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            .accessibilityIdentifier("startingLevel.\(choice.level).\(choice == .never ? "never" : "upTo")")
                        }
                    }
                    Button("あとで") { choose(nil) }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .keyboardShortcut(.cancelAction)
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background { AppBackground() }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    private func choose(_ choice: AppModel.StartingLevelChoice?) {
        model.applyStartingLevel(choice)
        dismiss()
    }
}
