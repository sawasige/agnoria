import SwiftUI

/// スコア帯クリアの演出（§4.3.1 [v1.5]）。セット完走でクリアしたとき、結果画面の前に 1 度だけ出す。
/// 女神が喜ぶ絵、クリアした帯のチェック、紙吹雪、ファンファーレ。「結果を見る」で結果へ。
/// [v1.8] 軸（単語 / 文法）ごとの帯。1 セットで 2 軸同時にクリアしたときは 1 画面にまとめる
struct StageClearView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var shown = false
    @State private var feedback = 0

    var body: some View {
        let clears = model.pendingStageClears.isEmpty
            ? [Stage.Clear(mode: .word, cleared: Stage.first, next: Stage.next(after: Stage.first))]
            : model.pendingStageClears
        ZStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                // アクセシビリティ文字サイズでは見出しを一段小さくし、絵も小さくして 1 画面に収める
                Text(title(clears))
                    .font(.system(typeSize.isAccessibilitySize ? .title : .largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Image("AgenoriaCheer")
                    .resizable()
                    .scaledToFit()
                    .frame(height: typeSize.isAccessibilitySize ? 150 : 260)
                    .scaleEffect(shown ? 1 : 0.85)
                    .opacity(shown ? 1 : 0)
                    .accessibilityHidden(true)
                VStack(spacing: 10) {
                    ForEach(clears, id: \.self) { clear in
                        HStack(spacing: 12) {
                            Text(clear.mode.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            StageChips(state: { level in
                                if level <= clear.cleared { return .cleared }
                                if level == clear.next { return .current }
                                return .locked
                            }, bounce: reduceMotion ? nil : clear.cleared)
                        }
                    }
                }
                .accessibilityHidden(true)
                Text(message(clears))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    model.showResultAfterStageClear()
                } label: {
                    Text("結果を見る")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title(clears))。\(message(clears))")

            if !reduceMotion {
                ConfettiView()
                    .ignoresSafeArea()
            }
        }
        .background { AppBackground() }
        .navigationBarBackButtonHidden(true)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sensoryFeedback(.success, trigger: feedback)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.7, bounce: 0.3).delay(0.1)) {
                shown = true
            }
            feedback += 1
            if settings.soundEffects {
                SoundEffects.shared.play(.fanfare)
            }
        }
    }

    /// 「単語 450 点帯クリア！」。2 軸同時で同じ帯なら「単語・文法 450 点帯クリア！」、違う帯なら 1 軸 1 行
    private func title(_ clears: [Stage.Clear]) -> String {
        grouped(clears, by: \.cleared)
            .map { level, modes in "\(modes) \(level) 点帯クリア！" }
            .joined(separator: "\n")
    }

    private func message(_ clears: [Stage.Clear]) -> String {
        grouped(clears, by: \.next)
            .map { next, modes in
                if let next { return "\(modes)は次に \(next) 点帯。おまかせでこの帯の問題が中心になります" }
                return "\(modes)はすべての帯を制覇しました。ここからは復習で定着させよう"
            }
            .joined(separator: "\n")
    }

    /// 同じ値の軸をまとめ、軸名を「単語・文法」のようにつなぐ（軸の順を保つ）
    private func grouped<Key: Hashable>(_ clears: [Stage.Clear], by key: KeyPath<Stage.Clear, Key>) -> [(Key, String)] {
        var order: [Key] = []
        var modes: [Key: [String]] = [:]
        for c in clears {
            let k = c[keyPath: key]
            if modes[k] == nil { order.append(k) }
            modes[k, default: []].append(c.mode.title)
        }
        return order.map { ($0, modes[$0]!.joined(separator: "・")) }
    }
}
