import SwiftUI
import AVFoundation

struct QuizView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    #endif
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
    /// ScrollView のスクロール位置（持ち上げ中の差し替え表示で再現する）
    @State private var scrollOffset: CGFloat = 0
    /// 最後に指が動いた時刻。全幅の選択肢ボタンは横に動かしても指を離すと押下になるので、直前にドラッグしていたら回答にしない
    @State private var lastDragAt = Date.distantPast
    /// カード領域の幅（GeometryReader の外の修飾子で 2 列かどうかを見るため）
    @State private var cardWidth: CGFloat = 0

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
            // 横に広い画面（iPad・iPhone Duo の内側・Mac・iPhone の横向き）では、回答後に解説を左、問題を右の 2 列にする（§4.2 [v2.0]）。
            // 縦が短い横向きでは解説が選択肢の下に隠れてスクロールしないと読めないため。size class ではなく使える幅で決める（Apple の指針）
            let wide = width >= 700
            // カードの重なり: 今の問題の下に次の問題（伏せ字）が小さく控えていて、めくるにつれて手前に出てくる
            let progress = min(1, max(0, -dragX / (width * 0.6)))
            ZStack(alignment: .top) {
                if dragX < 0 {
                    nextCard(run, wide: wide)
                        .scaleEffect(0.92 + 0.08 * progress)
                        .opacity(0.5 + 0.5 * progress)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                currentCard(run: run, question: q, answer: answer, width: width, progress: progress, wide: wide)
                .id(q.id)
                .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(swipeGesture(run: run, width: width))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
        .background { AppBackground() }
        .safeAreaInset(edge: .bottom) {
            if answer != nil, !(cardWidth >= 700 && isCompactHeight) {
                actionBar(run: run, question: q)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if answer != nil, cardWidth >= 700, isCompactHeight {
                actionBar(run: run, question: q)
                    .frame(width: cardWidth / 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 縦が短い横向きでは、タイトルバーを消して × だけ浮かせる（タイトルバーと操作列で縦の 4 割を使っていた）[v2.0]
        .overlay(alignment: .topLeading) {
            if isCompactHeight {
                Button { confirmLeave = true } label: {
                    Label("やめる", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                .clipShape(.circle)
                .padding(.leading, 8)
                .padding(.top, 4)
                .keyboardShortcut(.cancelAction)
            }
        }
        .animation(.default, value: answer != nil)
        .navigationTitle(run.config.categoryTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isCompactHeight ? .hidden : .visible, for: .navigationBar)
        #endif
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if !isCompactHeight {
                ToolbarItem(placement: .cancellationAction) {
                    Button { confirmLeave = true } label: { Label("やめる", systemImage: "xmark") }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .confirmationDialog("このセットをやめますか？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("やめてホームへ", role: .destructive) {
                Speaker.shared.stop()
                ListeningPlayer.shared.stop()
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

    /// 今の問題のカード。通常は ScrollView。持ち上げて傾けている間は、同じ内容をスクロール位置ごと再現した
    /// 普通のビューに差し替えて回転させる（UIKit の ScrollView を回転させるとセーフエリアが回転後の枠から
    /// 計算し直され、内容の上下の余白が動いてしまうため）
    /// 縦が短い（iPhone の横向き）。操作列を 1 行に詰める
    private var isCompactHeight: Bool {
        #if os(iOS)
        vSizeClass == .compact
        #else
        false
        #endif
    }

    private func currentCard(run: QuizRun, question q: QuizQuestion, answer: QuizRun.Answer?,
                             width: CGFloat, progress: CGFloat, wide: Bool) -> some View {
        Group {
            if dragX < 0 {
                // ScrollView の中と同じレイアウトにする: 幅を明示して高さは内容の自然な高さ。
                // 幅が不定のまま高さだけ固定すると、文字サイズが大きいときに問題文が 1 行ぶんの高さで配置され、
                // 描画は 2 行になって下の要素が上に寄る（実機で確認）
                cardContent(run: run, question: q, answer: answer, wide: wide)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: -scrollOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        cardContent(run: run, question: q, answer: answer, wide: wide)
                            .id("cardTop")
                    }
                    .scrollDisabled(dragAxis == .horizontal)
                    .onScrollGeometryChange(for: CGFloat.self) { g in
                        g.contentOffset.y + g.contentInsets.top
                    } action: { _, new in
                        scrollOffset = new
                    }
                    // 2 列のとき、下のほうで答えると左上の解説が画面の外に残るので、回答したら上端まで戻す [v2.0]
                    .onChange(of: answer != nil) { _, answered in
                        if wide, answered, scrollOffset > 0 {
                            withAnimation { proxy.scrollTo("cardTop", anchor: .top) }
                        }
                    }
                }
            }

        }
        // 持ち上げて傾けている間、カード内の Liquid Glass を平らな塗りに置き換える。
        // ガラスは回転すると回転前の外接矩形に膨らんで描かれ、行が縦に伸びて重なるため
        .environment(\.cardLifting, dragX < 0)
        // 持ち上げている間は 1 枚のカードに見せる: 背景を不透明にして下のカードが透けないようにし、角丸と影を付ける。
        // 影は背景に付ける（ScrollView に付けると中の要素ごとに影が出る）
        .clipShape(RoundedRectangle(cornerRadius: dragX < 0 ? 32 : 0, style: .continuous))
        // 背景は持ち上げた瞬間から不透明にする（フェードインさせると、先に現れる下のカードが透けて見える）
        .background {
            if dragX < 0 {
                AppBackground()
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: .black.opacity(0.25 * progress), radius: 24, y: 12)
            }
        }
        .offset(x: dragX)
        .rotationEffect(.degrees(Double(dragX / width) * 6), anchor: .bottom)
    }

    /// カードの中身: 番号・問題文・4 択・回答後の解説。
    /// wide なら最初から 2 列: 左に番号と進捗ドット（回答後はその下に正誤と解説）、右に問題と選択肢。
    /// 回答しても問題は動かさず、解説が左に現れるだけにする（問題が右へ寄る動きは不自然だった）
    private func cardContent(run: QuizRun, question q: QuizQuestion, answer: QuizRun.Answer?, wide: Bool) -> some View {
        Group {
            if wide {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 20) {
                        questionHeader(run: run, index: run.index, question: q)
                        if let answer {
                            explanationCard(answer: answer, question: q)
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    questionBody(q, answer: answer, interactive: true)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    questionHeader(run: run, index: run.index, question: q)
                    questionBody(q, answer: answer, interactive: true)
                    if let answer {
                        explanationCard(answer: answer, question: q)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: wide ? 1200 : 720)
        .frame(maxWidth: .infinity)
        .animation(.default, value: answer != nil)
    }

    /// 正誤と解説のカード
    private func explanationCard(answer: QuizRun.Answer, question q: QuizQuestion) -> some View {
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
        .fixedSize(horizontal: false, vertical: true)
        .glassCard()
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
            // タイトルバーを消しているときは、浮かせた × と重ならないように右へ寄せる
            .padding(.leading, isCompactHeight ? 52 : 0)
            .accessibilityElement(children: .combine)


            ProgressDots(run: run, index: index)
                .accessibilityHidden(true)
        }
    }

    /// 問題文と 4 択。interactive が false なら押せない飾り（次のカードの伏せ字用。キーボードショートカットも付けない）。
    /// リスニングは問題文の代わりに再生の案内、選択肢は回答まで伏せる（§4.2 [v1.9]）
    private func questionBody(_ q: QuizQuestion, answer: QuizRun.Answer?, interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if q.isListening {
                ListeningPrompt(question: q, number: (model.run?.questions.firstIndex(where: { $0.id == q.id }) ?? 0) + 1,
                                answered: answer != nil, interactive: interactive)
            } else {
                Text(q.prompt)
                    .font(q.wordFormat == .meaning
                          ? .system(.largeTitle, design: .serif, weight: .semibold)
                          : .title3)
                    .multilineTextAlignment(.leading)
                    // 持ち上げ中の差し替え表示（ScrollView の外）で高さを詰められて行が欠けないよう、自然な高さに固定
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 10) {
                ForEach(Array(q.choices.enumerated()), id: \.offset) { i, choice in
                    if interactive {
                        ChoiceButton(label: QuizQuestion.choiceLabels[i], text: choice,
                                     state: state(for: i, answer: answer, question: q),
                                     revealed: !q.isListening || answer != nil,
                                     playing: q.isListening && answer == nil && isPlaying(q, part: .response(i))) {
                            select(i)
                        }
                        .disabled(answer != nil)
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                    } else {
                        ChoiceButton(label: QuizQuestion.choiceLabels[i], text: choice, state: .idle,
                                     revealed: !q.isListening) {}
                            .disabled(true)
                    }
                }
            }
        }
    }

    private func isPlaying(_ q: QuizQuestion, part: ListeningPlayer.Part) -> Bool {
        let player = ListeningPlayer.shared
        return player.questionID == q.id && player.playing == part
    }

    /// めくった下に見える次のカード。レイアウトは本物と同じだが、問題文と選択肢は伏せ字にして先に読めないようにする。
    /// 最終問の下は結果の予告
    private func nextCard(_ run: QuizRun, wide: Bool) -> some View {
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
                if wide {
                    HStack(alignment: .top, spacing: 24) {
                        questionHeader(run: run, index: run.index + 1, question: next)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        questionBody(next, answer: nil, interactive: false)
                            .redacted(reason: .placeholder)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                } else {
                    questionHeader(run: run, index: run.index + 1, question: next)
                    questionBody(next, answer: nil, interactive: false)
                        .redacted(reason: .placeholder)
                }
            }
        }
        .padding()
        .frame(maxWidth: wide ? 1200 : 720)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }


    /// 回答後に画面下へ固定表示する操作列。親指の届く位置に 読み上げ / ブックマーク / 次へ をまとめる。
    /// 縦が短い横向き（compact 高さ）では 読み上げ / ブックマーク / 次へ を 1 行に並べ、スワイプのヒントは出さない [v2.0]
    @ViewBuilder
    private func actionBar(run: QuizRun, question q: QuizQuestion) -> some View {
        // アクセシビリティ文字サイズでは 読み上げ / ブックマーク を縦に積む
        let stacked = typeSize.isAccessibilitySize
        let oneRow = isCompactHeight && !stacked
        GlassEffectContainer(spacing: 10) {
            AnyLayout(oneRow ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 10))) {
                AnyLayout(stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
                    if q.isListening {
                        Button {
                            ListeningPlayer.shared.play(q, number: run.index + 1, rate: settings.speechRate)
                            model.analytics.log(.replayTapped)
                        } label: {
                            barLabel("もう一度聞く", "speaker.wave.2", iconOnly: oneRow)
                        }
                        .buttonStyle(.glass)
                    } else if let text = q.speechText {
                        Button {
                            Speaker.shared.speak(text, rate: settings.speechRate)
                            model.analytics.log(.speakTapped)
                        } label: {
                            barLabel("読み上げ", "speaker.wave.2", iconOnly: oneRow)
                        }
                        .buttonStyle(.glass)
                    }
                    if bookmarked {
                        Button { toggleBookmark(q) } label: {
                            barLabel("ブックマーク済み", "bookmark.fill", iconOnly: oneRow)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                    } else {
                        Button { toggleBookmark(q) } label: {
                            barLabel("ブックマーク", "bookmark", iconOnly: oneRow)
                        }
                        .buttonStyle(.glass)
                    }
                }

                #if os(iOS)
                if !settings.swipeHintDone && !oneRow {
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
            .controlSize(oneRow ? .regular : .large)
        }

        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    /// 操作列のボタンのラベル。1 行に詰めるときは記号だけ（幅が半分しかない横向きで文字が縦に折れるため）
    @ViewBuilder
    private func barLabel(_ title: String, _ systemImage: String, iconOnly: Bool) -> some View {
        if iconOnly {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 40)
        } else {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
    }

    /// 次へ（最終問は結果へ）。ボタンからはカードを送る動きなしで切り替える（クロスフェード）
    private func goNext(_ run: QuizRun) {
        guard !leaving else { return }
        Speaker.shared.stop()
        ListeningPlayer.shared.stop()
        withAnimation(.easeOut(duration: 0.25)) {
            if run.isLast { model.finishRun() } else { model.advance() }
        }
    }

    /// 左スワイプの確定: 今のカードを画面外まで送ってから次の問題に切り替える。下に見えていた伏せ字のカードが本物に変わる
    private func commitSwipe(run: QuizRun, width: CGFloat) {
        leaving = true
        Speaker.shared.stop()
        ListeningPlayer.shared.stop()
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
        // リスニングは回答で再生を止める（効果音と重ねない）。自動読み上げも無し
        if run.current.isListening { ListeningPlayer.shared.stop() }
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
        if q.isListening { return "自然な応答を選ぶ" }
        return switch q.wordFormat {
        case .meaning: "意味を選ぶ"
        case .cloze: "例文の空欄に入る語"
        case .jaToEn: "英語で言うと"
        case nil: q.categoryName
        }

    }
}

/// リスニングの問題文の場所（§4.2 [v1.9]）。回答前は案内と「聞く」ボタン、表示されたら自動で再生する。回答後は問いかけの英文
struct ListeningPrompt: View {
    let question: QuizQuestion
    /// セット内の番号（1 から）。「Number N.」と読む
    let number: Int
    let answered: Bool
    /// 次のカードの伏せ字では false（自動再生しない）
    let interactive: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @State private var volumeZero = false

    private var player: ListeningPlayer { ListeningPlayer.shared }
    private var playingThis: Bool { player.questionID == question.id && player.playing != nil }
    /// 番号か問いかけを読んでいる
    private var speakingQuestion: Bool { playingThis && (player.playing == .number || player.playing == .question) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if answered {
                Text(question.prompt)
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .accessibilityAddTraits(.isHeader)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: speakingQuestion ? "person.wave.2.fill" : "person.wave.2")
                        .font(.system(size: 34))
                        .foregroundStyle(speakingQuestion ? Color.accentColor : Color.secondary)
                        .symbolEffect(.variableColor.iterative, isActive: speakingQuestion)
                        .frame(width: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("問いかけと 3 つの応答を聞いて、いちばん自然な応答を選ぶ")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(volumeZero ? "音量が 0 になっています" : "文字は回答のあとに出ます")
                            .font(.caption)
                            .foregroundStyle(volumeZero ? Color.orange : Color.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Button {
                    play()
                    model.analytics.log(.replayTapped)
                } label: {
                    Label(playingThis ? "再生中…" : "聞く", systemImage: playingThis ? "waveform" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(!interactive)
                .keyboardShortcut(.space, modifiers: [])
            }
        }
        .padding(.vertical, 4)
        .task(id: question.id) {
            // 表示されたら少し待って自動で再生。回答済み・伏せ字・すでに再生中なら何もしない
            guard interactive, !answered, player.questionID != question.id else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            play()
        }
    }

    private func play() {
        #if os(iOS)
        volumeZero = AVAudioSession.sharedInstance().outputVolume == 0
        #endif
        player.play(question, number: number, rate: settings.speechRate)
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


