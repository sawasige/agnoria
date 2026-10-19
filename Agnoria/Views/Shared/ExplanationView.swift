import SwiftUI

/// 回答後の解説。文法: 完成した英文 + 和訳 + explanation [v1.7] / 単語: 意味 + 例文 + 和訳（練習問題は生成文とその和訳）。
/// Foundation Models の言い換え付き。
/// 背景は持たない（呼び出し側のガラスカードに載せる）
struct ExplanationView: View {
    let question: QuizQuestion
    @Environment(AppModel.self) private var model
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
                if question.isPractice {
                    // 類題: 元の単語の例文ではなく、生成した文とその和訳
                    completedSentence.font(.callout)
                    if let ja = question.promptJa {
                        Text(ja).font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    Text(w.example).font(.callout)
                    Text(w.exampleJa).font(.callout).foregroundStyle(.secondary)
                }
            } else {
                completedSentence.font(.callout)
                if let ja = question.promptJa, !ja.isEmpty {
                    Text(ja).font(.callout).foregroundStyle(.secondary)
                }
                Divider()
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

    /// 空欄を正解で埋めた英文。正解の部分だけ太字にする
    private var completedSentence: Text {
        let answer = question.choices[question.correctIndex]
        let parts = question.prompt.components(separatedBy: Cloze.blank)
        guard parts.count > 1 else { return Text(question.prompt) }
        var text = Text(parts[0])
        for part in parts.dropFirst() {
            text = text + Text(answer).bold() + Text(part)
        }
        return text
    }

    private func rephrase() async {
        aiLoading = true
        defer { aiLoading = false }
        model.analytics.log(.rephraseUsed)
        if let text = await AIAssist.rephrase(explanation: question.explanation), !text.isEmpty {
            rephrased = text
        } else {
            aiHidden = true  // 失敗時は静かに消す（§5）
        }
    }
}
