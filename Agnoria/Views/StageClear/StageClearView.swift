import SwiftUI

/// スコア帯クリアの演出（§4.3.1 [v1.5]）。セット完走でクリアしたとき、結果画面の前に 1 度だけ出す。
/// 女神が喜ぶ絵、クリアした帯のチェック、紙吹雪、ファンファーレ。「結果を見る」で結果へ
struct StageClearView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var shown = false
    @State private var feedback = 0

    var body: some View {
        let clear = model.pendingStageClear ?? Stage.Clear(cleared: Stage.first, next: Stage.next(after: Stage.first))
        ZStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                // アクセシビリティ文字サイズでは見出しを一段小さくし、絵も小さくして 1 画面に収める
                Text("\(clear.cleared) 点帯クリア！")
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
                StageChips(state: { level in
                    if level <= clear.cleared { return .cleared }
                    if level == clear.next { return .current }
                    return .locked
                }, bounce: reduceMotion ? nil : clear.cleared)
                .accessibilityHidden(true)
                Text(message(clear))
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
            .accessibilityLabel("\(clear.cleared) 点帯クリア。\(message(clear))")

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

    private func message(_ clear: Stage.Clear) -> String {
        if let next = clear.next {
            return "次は \(next) 点帯。おまかせがこの帯の問題中心になります"
        }
        return "すべての帯を制覇しました。ここからは復習で定着させよう"
    }
}
