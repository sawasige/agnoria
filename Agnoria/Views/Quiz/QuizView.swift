import SwiftUI

struct QuizView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var confirmLeave = false
    @State private var bookmarked = false
    @State private var feedbackCount = 0
    @State private var lastCorrect = true

    var body: some View {
        if let run = model.run {
            content(run)
        } else {
            ContentUnavailableView("セットがありません", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder
    private func content(_ run: QuizRun) -> some View {
        let q = run.current
        let answer = run.currentAnswer
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("\(run.index + 1) / \(run.questions.count)")
                        .font(.subheadline.monospacedDigit())
                    Spacer()
                    Text(formatLabel(q))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                ProgressDots(run: run)
                    .accessibilityHidden(true)

                Text(q.prompt)
                    .font(q.wordFormat == .meaning
                          ? .system(.largeTitle, design: .serif, weight: .semibold)
                          : .title3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 10) {
                    ForEach(Array(q.choices.enumerated()), id: \.offset) { i, choice in
                        ChoiceButton(label: QuizQuestion.choiceLabels[i], text: choice,
                                     state: state(for: i, answer: answer, question: q)) {
                            select(i)
                        }
                        .disabled(answer != nil)
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                    }
                }

                if let answer {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: answer.isCorrect ? "checkmark.seal.fill" : "xmark.seal.fill")
                                .font(.title2)
                                .symbolEffect(.bounce, options: .nonRepeating, value: answer)
                            Text(answer.isCorrect ? "正解" : "不正解")
                                .font(.title3.weight(.bold))
                                .fontDesign(.rounded)
                        }
                        .foregroundStyle(answer.isCorrect ? Color.green : Color.red)
                        ExplanationView(question: q)
                            .id(q.id)
                    }
                    .glassCard()
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .animation(.default, value: answer != nil)
        }
        .background { AppBackground() }
        .safeAreaInset(edge: .bottom) {
            if answer != nil {
                actionBar(run: run, question: q)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: answer != nil)
        .navigationTitle(run.config.categoryTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { confirmLeave = true } label: { Label("やめる", systemImage: "xmark") }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .confirmationDialog("このセットをやめますか？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("やめてホームへ", role: .destructive) {
                Speaker.shared.stop()
                model.abandonRun()
            }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("ここまでの回答は記録済みですが、セットの記録は残りません。")
        }
        .onChange(of: q.id, initial: true) { _, _ in
            bookmarked = model.isBookmarked(q.itemID)
        }
        .sensoryFeedback(trigger: feedbackCount) { _, _ in lastCorrect ? .success : .error }
    }

    /// 回答後に画面下へ固定表示する操作列。親指の届く位置に 読み上げ / ブックマーク / 次へ をまとめる
    @ViewBuilder
    private func actionBar(run: QuizRun, question q: QuizQuestion) -> some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    if let text = q.speechText {
                        Button {
                            Speaker.shared.speak(text, rate: settings.speechRate)
                        } label: {
                            Label("読み上げ", systemImage: "speaker.wave.2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    if bookmarked {
                        Button { toggleBookmark(q) } label: {
                            Label("ブックマーク済み", systemImage: "bookmark.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                    } else {
                        Button { toggleBookmark(q) } label: {
                            Label("ブックマーク", systemImage: "bookmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                }

                Button {
                    Speaker.shared.stop()
                    if run.isLast { model.finishRun() } else { model.advance() }
                } label: {
                    Text(run.isLast ? "結果を見る" : "次へ")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func toggleBookmark(_ q: QuizQuestion) {
        model.toggleBookmark(q.itemID)
        bookmarked = model.isBookmarked(q.itemID)
    }

    private func select(_ index: Int) {
        guard let run = model.run, !run.isAnswered else { return }
        model.answerCurrent(index)
        guard let a = run.currentAnswer else { return }
        lastCorrect = a.isCorrect
        feedbackCount += 1
        if settings.soundEffects {
            SoundEffects.shared.play(a.isCorrect ? .correct : .wrong)
        }
        if settings.autoSpeak, let text = run.current.speechText {
            // 効果音にかぶらないよう少し待つ。待っている間に次へ進んだら読まない
            let questionID = run.current.id
            Task {
                try? await Task.sleep(for: settings.autoSpeakDelay)
                guard model.run === run, run.current.id == questionID else { return }
                Speaker.shared.speak(text, rate: settings.speechRate)
            }
        }
        AccessibilityNotification.Announcement(a.isCorrect ? "正解" : "不正解。正解は \(QuizQuestion.choiceLabels[run.current.correctIndex])").post()
    }

    private func state(for i: Int, answer: QuizRun.Answer?, question: QuizQuestion) -> ChoiceButton.State {
        guard let answer else { return .idle }
        if i == question.correctIndex { return .correct }
        if i == answer.chosenIndex { return .wrong }
        return .dimmed
    }

    private func formatLabel(_ q: QuizQuestion) -> String {
        switch q.wordFormat {
        case .meaning: "意味を選ぶ"
        case .cloze: "例文の空欄に入る語"
        case .jaToEn: "英語で言うと"
        case nil: q.categoryName
        }
    }
}

/// 10問ぶんの進捗ドット。回答済みは正誤の色、現在の問題はアクセント
struct ProgressDots: View {
    let run: QuizRun

    var body: some View {
        HStack(spacing: 5) {
            ForEach(run.questions.indices, id: \.self) { i in
                Capsule()
                    .fill(color(at: i))
                    .frame(height: 6)
                    .overlay {
                        if i == run.index {
                            Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.4), value: run.answers.count)
    }

    private func color(at i: Int) -> Color {
        if run.answers.indices.contains(i) {
            return run.answers[i].isCorrect ? .green : .red
        }
        return i == run.index ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2)
    }
}
