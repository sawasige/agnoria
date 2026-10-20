import SwiftUI
import StoreKit

struct ResultView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.requestReview) private var requestReview
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
                VStack(spacing: 14) {
                    HStack(alignment: .bottom, spacing: 4) {
                        AgenoriaFace(expression: .forScore(correct: run.correctCount, total: run.questions.count))
                        ScoreRing(correct: run.correctCount, total: run.questions.count)
                    }
                    Text(message(correct: run.correctCount, total: run.questions.count))
                        .font(.headline)
                        .fontDesign(.rounded)
                    HStack(spacing: 6) {
                        Text((run.config.mode.map { $0.title + " ・ " } ?? "") + run.config.categoryTitle)
                        Text("・")
                        Text("正解 \(run.correctCount)").foregroundStyle(.green)
                        Text("不正解 \(run.questions.count - run.correctCount)").foregroundStyle(.red)
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(run.questions.count)問中\(run.correctCount)問正解。\(message(correct: run.correctCount, total: run.questions.count))")

                ForEach(model.lastUnlocked, id: \.self) { opened in
                    if let level = opened.next {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.open.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(opened.mode.title) \(level) 点帯が開きました").font(.headline).fontDesign(.rounded)
                                Text("次のおまかせからこの帯の問題が中心になります").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .glassCard(padding: 14, cornerRadius: 16)
                        .transition(.scale.combined(with: .opacity))
                    }
                }

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
                    .buttonStyle(.glassProminent)

                    if !wrong.isEmpty {
                        Button {
                            var config = run.config
                            config.filter = .all
                            config.restrictTo = Set(wrong.map(\.question.itemID))
                            if model.startQuiz(config) == nil { model.goHome() }
                        } label: {
                            Text("間違えた問題だけやり直す").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }

                    Button {
                        model.goHome()
                    } label: {
                        Text("ホームへ").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { AppBackground() }
        .navigationTitle("結果")
        .navigationBarBackButtonHidden(true)
        .sheet(item: $practice) { q in
            PracticeQuestionView(question: q)
        }
        .task {
            // 結果を見てから頼む（§4.8 [v1.8]）。その前に画面を離れたら頼まない
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, model.consumeReviewRequest() else { return }
            requestReview()
        }
    }

    private func message(correct: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        let ratio = Double(correct) / Double(total)
        switch ratio {
        case 1: return "全問正解！"
        case 0.8...: return "いい調子"
        case 0.5...: return "もう一歩"
        default: return "苦手が見つかった。もう1セットいこう"
        }
    }

    private func generatePractice(for question: QuizQuestion) async {
        guard let w = question.word else { return }
        generatingFor = question.itemID
        defer { generatingFor = nil }
        model.analytics.log(.practiceUsed)
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
        .tint(.primary)
        .glassCard(padding: 14, cornerRadius: 16)
    }
}

/// 正答数の円形ゲージ。表示時に 0 から伸びる
struct ScoreRing: View {
    let correct: Int
    let total: Int
    @State private var shown = false

    private var ratio: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    private var color: Color {
        switch ratio {
        case 0.8...: .green
        case 0.5...: Color.accentColor
        default: .orange
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 12)
            Circle()
                .trim(from: 0, to: shown ? ratio : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(correct)")
                    .font(.system(size: 50, weight: .bold, design: .rounded).monospacedDigit())
                Text("/ \(total)")
                    .font(.title3.monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 160, height: 160)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.15).delay(0.1)) { shown = true }
        }
        .accessibilityHidden(true)
    }
}

/// Foundation Models が生成した練習問題（1問・履歴に記録しない）
struct PracticeQuestionView: View {
    let question: QuizQuestion
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
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
                            .glassCard()
                            .sensoryFeedback(chosen == question.correctIndex ? .success : .error, trigger: chosen)
                        if let text = question.speechText {
                            Button {
                                Speaker.shared.speak(text, rate: settings.speechRate)
                                model.analytics.log(.speakTapped)
                            } label: {
                                Label("読み上げ", systemImage: "speaker.wave.2")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .padding()
            }
            .background { AppBackground() }
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
