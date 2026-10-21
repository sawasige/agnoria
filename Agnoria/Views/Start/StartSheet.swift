import SwiftUI

/// 学習の選択シート（§4.10 [v1.9]）。ホームの「選んで始める」から開く。
/// 種類ごとの「10 問」（その種類のミックス）と「分野を選ぶ」（PickView）、復習（間違えた / ブックマーク）、
/// おまかせの設定（リスニングも混ぜる）。学習開始に関する選択はここに集め、ダッシュボードには置かない
struct StartSheet: View {
    let tracks: [Stage.Track]
    let wrong: Int
    let bookmarked: Int
    /// 選んだ条件で始める（呼び出し側がシートを閉じてセットを始める）
    let start: (QuizConfig) -> Void

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 中身の高さ。最初の高さをこれに合わせる（半分の高さだと末尾のトグルが切れるため）
    @State private var contentHeight: CGFloat = 0
    /// ナビゲーションバーとつまみの分
    private static let chromeHeight: CGFloat = 72

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(DrillMode.allCases, id: \.self) { mode in
                        kindRow(mode)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("復習", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        HStack(spacing: 12) {
                            Button { start(QuizConfig(mode: nil, category: nil, format: nil, filter: .wrongOnly)) } label: {
                                Label("間違えた \(wrong)", systemImage: "arrow.counterclockwise")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(wrong == 0)
                            Button { start(QuizConfig(mode: nil, category: nil, format: nil, filter: .bookmarked)) } label: {
                                Label("ブックマーク \(bookmarked)", systemImage: "bookmark")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(bookmarked == 0)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $settings.autoIncludesListening) {
                            Label("おまかせにリスニングも混ぜる", systemImage: "sparkles")
                                .font(.headline)
                        }
                        .accessibilityIdentifier("autoListeningToggle")
                        .onChange(of: settings.autoIncludesListening) {
                            model.analytics.log(.settingsChanged(key: "autoIncludesListening"))
                        }
                        Text("オンにすると、おまかせと復習に応答問題が混ざります。音の出せる場所で。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .glassCard()
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .background { AppBackground() }
            .navigationTitle("選んで始める")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: DrillMode.self) { mode in
                PickView(mode: mode, onStart: start)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        #if os(iOS)
        // 中身がちょうど収まる高さで開き、収まらない端末や文字サイズでは全画面（それでも足りなければ中がスクロール）
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + Self.chromeHeight), .large] : [.large])
        .presentationDragIndicator(.visible)
        #else

        .frame(minWidth: 440, minHeight: 520)
        #endif
    }

    /// 種類の行: 記号・名前・今の帯、「10 問」、「分野を選ぶ ›」
    private func kindRow(_ mode: DrillMode) -> some View {
        let track = tracks.first { $0.mode == mode }
        let stacked = typeSize.isAccessibilitySize
        return AnyLayout(stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))) {
            HStack(spacing: 10) {
                Image(systemName: Self.symbol(mode))
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.headline)
                    Text(track.map { "\($0.current) 点帯" } ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !stacked { Spacer(minLength: 0) }
            }
            HStack(spacing: 8) {
                Button { start(QuizConfig(mode: mode, category: nil, format: nil)) } label: {
                    Text("10 問")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("\(mode.title)で10問")
                NavigationLink(value: mode) {
                    HStack(spacing: 4) {
                        Text("分野")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(mode.title)の分野を選ぶ")
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
        .disabled((track?.summary.total ?? 0) == 0)
    }

    /// 種類の記号（分野の記号とは別。種類そのものを表す）
    static func symbol(_ mode: DrillMode) -> String {
        switch mode {
        case .word: "character.book.closed"
        case .grammar: "text.quote"

        case .listening: "ear"
        }
    }
}
