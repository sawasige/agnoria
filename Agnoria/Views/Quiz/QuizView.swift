import SwiftUI

struct QuizView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var confirmLeave = false
    @State private var bookmarked = false
    @State private var feedbackCount = 0
    @State private var lastCorrect = true
    /// 左スワイプ中の横ずれ（右へは動かさない）。確定後は画面外まで動かしてから次の問題に切り替える
    @State private var dragX: CGFloat = 0
    /// ドラッグの向き。最初に決めて指を離すまで変えない（横なら縦スクロールを止める）
    @State private var dragAxis: Axis?
    /// カードが画面外へ抜けるアニメーション中
    @State private var leaving = false
    /// 最後に指が動いた時刻。全幅の選択肢ボタンは横に動かしても指を離すと押下になるので、直前にドラッグしていたら回答にしない
    @State private var lastDragAt = Date.distantPast

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
        GeometryReader { geo in
            let width = geo.size.width
            // カードの重なり: 今の問題の下に次の問題（伏せ字）が小さく控えていて、めくるにつれて手前に出てくる
            let progress = min(1, max(0, -dragX / (width * 0.6)))
            ZStack(alignment: .top) {
                if dragX < 0 {
                    nextCard(run)
                        .scaleEffect(0.92 + 0.08 * progress)
                        .opacity(0.5 + 0.5 * progress)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        questionHeader(run: run, index: run.index, question: q)
                        questionBody(q, answer: answer, interactive: true)

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
                .scrollDisabled(dragAxis == .horizontal)
                // 持ち上げて傾けている間、カード内の Liquid Glass を平らな塗りに置き換える。
                // ガラスは回転すると回転前の外接矩形に膨らんで描かれ、行が縦に伸びて重なるため
                .environment(\.cardLifting, dragX < 0)
                // 持ち上げている間は 1 枚のカードに見せる: 背景を不透明にして下のカードが透けないようにし、角丸と影を付ける。
                // 影は背景に付ける（ScrollView に付けると中の要素ごとに影が出る）
                .clipShape(RoundedRectangle(cornerRadius: dragX < 0 ? 32 : 0, style: .continuous))
                .background {
                    AppBackground()
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .shadow(color: .black.opacity(0.25 * progress), radius: 24, y: 12)
                        .opacity(min(1, progress * 4))
                }
                .offset(x: dragX)
                .rotationEffect(.degrees(Double(dragX / width) * 6), anchor: .bottom)
                .id(q.id)
                .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(swipeGesture(run: run, width: width))
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

    /// 番号・形式名・進捗ドット
    private func questionHeader(run: QuizRun, index: Int, question q: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("\(index + 1) / \(run.questions.count)")
                    .font(.subheadline.monospacedDigit())
                Spacer()
                Text(formatLabel(q))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            ProgressDots(run: run, index: index)
                .accessibilityHidden(true)
        }
    }

    /// 問題文と 4 択。interactive が false なら押せない飾り（次のカードの伏せ字用。キーボードショートカットも付けない）
    private func questionBody(_ q: QuizQuestion, answer: QuizRun.Answer?, interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
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
                    if interactive {
                        ChoiceButton(label: QuizQuestion.choiceLabels[i], text: choice,
                                     state: state(for: i, answer: answer, question: q)) {
                            select(i)
                        }
                        .disabled(answer != nil)
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                    } else {
                        ChoiceButton(label: QuizQuestion.choiceLabels[i], text: choice, state: .idle) {}
                            .disabled(true)
                    }
                }
            }
        }
    }

    /// めくった下に見える次のカード。レイアウトは本物と同じだが、問題文と選択肢は伏せ字にして先に読めないようにする。
    /// 最終問の下は結果の予告
    private func nextCard(_ run: QuizRun) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if run.isLast {
                VStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                    Text("結果")
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else {
                let next = run.questions[run.index + 1]
                questionHeader(run: run, index: run.index + 1, question: next)
                questionBody(next, answer: nil, interactive: false)
                    .redacted(reason: .placeholder)
            }
        }
        .padding()
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
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

                #if os(iOS)
                if !settings.swipeHintDone {
                    Text("← 左にスワイプでも次へ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                        .transition(.opacity)
                }
                #endif
                Button {
                    goNext(run)
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

    /// 次へ（最終問は結果へ）。ボタンからはカードを送る動きなしで切り替える（クロスフェード）
    private func goNext(_ run: QuizRun) {
        guard !leaving else { return }
        Speaker.shared.stop()
        withAnimation(.easeOut(duration: 0.25)) {
            if run.isLast { model.finishRun() } else { model.advance() }
        }
    }

    /// 左スワイプの確定: 今のカードを画面外まで送ってから次の問題に切り替える。下に見えていた伏せ字のカードが本物に変わる
    private func commitSwipe(run: QuizRun, width: CGFloat) {
        leaving = true
        Speaker.shared.stop()
        if !settings.swipeHintDone {
            withAnimation { settings.swipeHintDone = true }
        }
        withAnimation(.easeIn(duration: 0.22)) {
            dragX = -width * 1.2
        } completion: {
            withAnimation(.easeOut(duration: 0.25)) {
                if run.isLast { model.finishRun() } else { model.advance() }
                dragX = 0
            }
            leaving = false
        }
    }

    /// 回答後だけ効く左スワイプ（§4.2 [v1.4]）。最初の動きで縦か横かを決め、横なら縦スクロールを止めてカードを指に追従させる
    private func swipeGesture(run: QuizRun, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                lastDragAt = .now
                guard !leaving else { return }
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal, run.isAnswered else { return }
                dragX = min(0, value.translation.width)
            }
            .onEnded { value in
                let axis = dragAxis
                dragAxis = nil
                guard !leaving, axis == .horizontal, run.isAnswered else { return }
                if SwipeNext.triggers(translation: value.translation, predicted: value.predictedEndTranslation) {
                    commitSwipe(run: run, width: width)
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { dragX = 0 }
                }
            }
    }

    private func toggleBookmark(_ q: QuizQuestion) {
        model.toggleBookmark(q.itemID)
        bookmarked = model.isBookmarked(q.itemID)
    }

    private func select(_ index: Int) {
        guard let run = model.run, !run.isAnswered else { return }
        // 横スワイプの指離しをタップと区別する（§4.2 [v1.4]）
        guard Date.now.timeIntervalSince(lastDragAt) > 0.3 else { return }
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
    /// 現在として強調する位置。省略時は run.index（次のカードの伏せ字では +1）
    var index: Int? = nil

    private var current: Int { index ?? run.index }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(run.questions.indices, id: \.self) { i in
                Capsule()
                    .fill(color(at: i))
                    .frame(height: 6)
                    .overlay {
                        if i == current {
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
        return i == current ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2)
    }
}
