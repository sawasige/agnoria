import SwiftUI

struct QuizView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var confirmLeave = false
    @State private var bookmarked = false

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

                ProgressView(value: Double(run.index + (answer == nil ? 0 : 1)), total: Double(run.questions.count))
                    .accessibilityHidden(true)

                Text(q.prompt)
                    .font(q.wordFormat == .meaning ? .largeTitle.bold() : .title3)
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
                        Text(answer.isCorrect ? "正解" : "不正解")
                            .font(.headline)
                            .foregroundStyle(answer.isCorrect ? .green : .red)
                        ExplanationView(question: q)
                            .id(q.id)
                    }
                    .transition(.opacity)
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .animation(.default, value: answer != nil)
        }
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
    }

    /// 回答後に画面下へ固定表示する操作列。親指の届く位置に 読み上げ / ブックマーク / 次へ をまとめる
    @ViewBuilder
    private func actionBar(run: QuizRun, question q: QuizQuestion) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let text = q.speechText {
                    Button {
                        Speaker.shared.speak(text, rate: settings.speechRate)
                    } label: {
                        Label("読み上げ", systemImage: "speaker.wave.2")
                            .frame(maxWidth: .infinity)
                    }
                }
                Button {
                    model.toggleBookmark(q.itemID)
                    bookmarked = model.isBookmarked(q.itemID)
                } label: {
                    Label(bookmarked ? "ブックマーク済み" : "ブックマーク",
                          systemImage: bookmarked ? "bookmark.fill" : "bookmark")
                        .frame(maxWidth: .infinity)
                }
                .tint(bookmarked ? .orange : nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                Speaker.shared.stop()
                if run.isLast { model.finishRun() } else { model.advance() }
            } label: {
                Text(run.isLast ? "結果を見る" : "次へ")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func select(_ index: Int) {
        guard let run = model.run, !run.isAnswered else { return }
        model.answerCurrent(index)
        if settings.autoSpeak, let text = run.current.speechText {
            Speaker.shared.speak(text, rate: settings.speechRate)
        }
        if let a = run.currentAnswer {
            AccessibilityNotification.Announcement(a.isCorrect ? "正解" : "不正解。正解は \(QuizQuestion.choiceLabels[run.current.correctIndex])").post()
        }
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
