import SwiftUI

/// 単語 cloze の「類題を出す」（§5）。回答直後の解説と、結果画面の間違えた問題に出す。
/// 作れなかったときはボタンを残して一言出し、押し直せるようにする（[v2.2] 以前は静かに消していて、初回はほぼ失敗していた）
struct PracticeButton: View {
    let word: WordSnapshot
    @Environment(AppModel.self) private var model
    @State private var generating = false
    @State private var failed = false
    @State private var practice: QuizQuestion?

    /// この問題に類題を出せるか（Apple Intelligence が使え、単語の穴埋めで、練習用の問題ではない）
    static func isOffered(for q: QuizQuestion) -> Bool {
        AIAssist.isAvailable && q.wordFormat == .cloze && q.word != nil && !q.isPractice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await generate() }
            } label: {
                if generating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("作成中…")
                    }
                } else {
                    Label("類題を出す", systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(generating)
            if failed {
                Text("類題を作れませんでした。もう一度お試しください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $practice) { q in
            PracticeQuestionView(question: q)
        }
    }

    private func generate() async {
        generating = true
        failed = false
        defer { generating = false }
        model.analytics.log(.practiceUsed)
        if let q = await AIAssist.practiceCloze(for: word) {
            practice = q
        } else {
            failed = true
        }
    }
}
