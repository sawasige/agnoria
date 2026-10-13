import SwiftUI

struct ResultView: View {
    @Environment(AppModel.self) private var model
    @State private var practice: QuizQuestion?
    @State private var aiHidden = !AIAssist.isAvailable
    @State private var generatingFor: String?

    var body: some View {
        if let run = model.run {
            content(run)
        } else {
            ContentUnavailableView("結果がありません", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder
    private func content(_ run: QuizRun) -> some View {
        let wrong = run.wrongAnswers
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(run.correctCount) / \(run.questions.count)")
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    Text(run.config.mode.map { $0.title + " ・ " } ?? "" + run.config.categoryTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(run.questions.count)問中\(run.correctCount)問正解")

                if !wrong.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("間違えた問題").font(.headline)
                        ForEach(wrong, id: \.question.id) { a in
                            WrongAnswerRow(answer: a, aiHidden: aiHidden,
                                           generating: generatingFor == a.question.itemID) {
                                Task { await generatePractice(for: a.question) }
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        if model.startQuiz(run.config) == nil { model.goHome() }
                    } label: {
                        Text("同じ条件でもう1セット").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if !wrong.isEmpty {
                        Button {
                            var config = run.config
                            config.filter = .all
                            config.restrictTo = Set(wrong.map(\.question.itemID))
                            if model.startQuiz(config) == nil { model.goHome() }
                        } label: {
                            Text("間違えた問題だけやり直す").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        model.goHome()
                    } label: {
                        Text("ホームへ").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("結果")
        .navigationBarBackButtonHidden(true)
        .sheet(item: $practice) { q in
            PracticeQuestionView(question: q)
        }
    }

    private func generatePractice(for question: QuizQuestion) async {
        guard let w = question.word else { return }
        generatingFor = question.itemID
        defer { generatingFor = nil }
        if let q = await AIAssist.practiceCloze(for: w) {
            practice = q
        } else {
            aiHidden = true
        }
    }
}

struct WrongAnswerRow: View {
    let answer: QuizRun.Answer
    let aiHidden: Bool
    let generating: Bool
    let onPractice: () -> Void
    @State private var expanded = false

    var body: some View {
        let q = answer.question
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("正解").font(.caption).foregroundStyle(.secondary)
                    Text(q.choices[q.correctIndex]).font(.body.weight(.semibold)).foregroundStyle(.green)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("あなた").font(.caption).foregroundStyle(.secondary)
                    Text(q.choices[answer.chosenIndex]).font(.body).foregroundStyle(.red)
                }
                ExplanationView(question: q)
                if !aiHidden, q.wordFormat == .cloze, q.word != nil {
                    Button(action: onPractice) {
                        if generating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("類題を出す", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(generating)
                }
            }
            .padding(.top, 6)
        } label: {
            Text(q.prompt)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .lineLimit(expanded ? nil : 2)
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Foundation Models が生成した練習問題（1問・履歴に記録しない）
struct PracticeQuestionView: View {
    let question: QuizQuestion
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var chosen: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("練習用（記録されません）", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(question.prompt)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 10) {
                        ForEach(Array(question.choices.enumerated()), id: \.offset) { i, c in
                            ChoiceButton(label: QuizQuestion.choiceLabels[i], text: c, state: state(i)) {
                                guard chosen == nil else { return }
                                chosen = i
                                let correct = i == question.correctIndex
                                if settings.soundEffects {
                                    SoundEffects.shared.play(correct ? .correct : .wrong)
                                }
                                if settings.autoSpeak, let text = question.speechText {
                                    Task {
                                        try? await Task.sleep(for: settings.autoSpeakDelay)
                                        Speaker.shared.speak(text, rate: settings.speechRate)
                                    }
                                }
                            }
                            .disabled(chosen != nil)
                        }
                    }
                    if chosen != nil {
                        ExplanationView(question: question)
                            .sensoryFeedback(chosen == question.correctIndex ? .success : .error, trigger: chosen)
                        if let text = question.speechText {
                            Button {
                                Speaker.shared.speak(text, rate: settings.speechRate)
                            } label: {
                                Label("読み上げ", systemImage: "speaker.wave.2")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("類題")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func state(_ i: Int) -> ChoiceButton.State {
        guard let chosen else { return .idle }
        if i == question.correctIndex { return .correct }
        if i == chosen { return .wrong }
        return .dimmed
    }
}
