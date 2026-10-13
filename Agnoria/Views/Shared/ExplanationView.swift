import SwiftUI

/// 回答後の解説。文法: explanation / 単語: 意味 + 例文 + 和訳。Foundation Models の言い換え付き。
/// 背景は持たない（呼び出し側のガラスカードに載せる）
struct ExplanationView: View {
    let question: QuizQuestion
    @State private var rephrased: String?
    @State private var aiHidden = !AIAssist.isAvailable
    @State private var aiLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let w = question.word {
                HStack(alignment: .firstTextBaseline) {
                    Text(w.word).font(.title3.bold())
                    Text(w.pos).font(.caption).foregroundStyle(.secondary)
                }
                Text(w.meaning).font(.body)
                Divider()
                Text(w.example).font(.callout)
                Text(w.exampleJa).font(.callout).foregroundStyle(.secondary)
            } else {
                Text(question.explanation).font(.body)
            }

            if let rephrased {
                Divider()
                Label {
                    Text(rephrased).font(.callout)
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(.secondary)
                }
            } else if !aiHidden, question.mode == .grammar, !question.isPractice {
                Button {
                    Task { await rephrase() }
                } label: {
                    if aiLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("別の言い方で", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(aiLoading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rephrase() async {
        aiLoading = true
        defer { aiLoading = false }
        if let text = await AIAssist.rephrase(explanation: question.explanation), !text.isEmpty {
            rephrased = text
        } else {
            aiHidden = true  // 失敗時は静かに消す（§5）
        }
    }
}
