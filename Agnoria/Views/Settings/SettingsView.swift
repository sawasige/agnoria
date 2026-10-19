import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset1 = false
    @State private var confirmReset2 = false
    @State private var resetDone = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("到達帯", selection: $settings.unlockedLevel) {
                        ForEach(Stage.levels, id: \.self) { Text("\($0) 点帯").tag($0) }
                    }
                } header: {
                    Text("ステージ")
                } footer: {
                    Text("おまかせと分野タイルは、到達帯までのスコア帯から出題します。帯の習得率が 80% になると自動で次の帯へ進みます。先に進みたい・戻りたいときはここで変えられます。")
                }

                Section("音") {
                    Toggle("正解・不正解の効果音", isOn: $settings.soundEffects)
                        .accessibilityIdentifier("soundEffectsToggle")
                    Toggle("回答後に例文を自動で読み上げる", isOn: $settings.autoSpeak)
                        .accessibilityIdentifier("autoSpeakToggle")
                    VStack(alignment: .leading) {
                        Slider(value: $settings.speechRate, in: AppSettings.speechRateRange, step: 0.05) {
                            Text("速度")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                        .accessibilityValue(String(format: "%.2f", settings.speechRate))
                    }
                    Button {
                        Speaker.shared.speak("Please pay the invoice within 30 days.", rate: settings.speechRate)
                    } label: {
                        Label("試し聞き", systemImage: "speaker.wave.2")
                    }
                }

                Section {
                    Button("学習履歴をリセット", role: .destructive) { confirmReset1 = true }
                } footer: {
                    Text("正誤の記録・ブックマーク・連続日数が消えます。問題データは残ります。")
                }

                Section("このアプリについて") {
                    LabeledContent("バージョン", value: versionString)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agnoria（アグノリア）").font(.headline)
                        Text("ギリシャ語 Agnoia（無知）と、ローマの女神 Agenoria（子どもに学ぶ力を授ける）から。「無知から学び始める」の意。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("設定")
            .onChange(of: settings.soundEffects) { model.analytics.log(.settingsChanged(key: "soundEffects")) }
            .onChange(of: settings.autoSpeak) { model.analytics.log(.settingsChanged(key: "autoSpeak")) }
            .onChange(of: settings.speechRate) { model.analytics.log(.settingsChanged(key: "speechRate")) }
            .onChange(of: settings.unlockedLevel) {
                model.analytics.log(.settingsChanged(key: "unlockedLevel"))
                model.analytics.syncUserProperties()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .confirmationDialog("学習履歴をリセットしますか？", isPresented: $confirmReset1, titleVisibility: .visible) {
                Button("次へ", role: .destructive) { confirmReset2 = true }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。")
            }
            .alert("本当にリセットしますか？", isPresented: $confirmReset2) {
                Button("リセットする", role: .destructive) {
                    resetDone = (try? model.resetHistory()) != nil
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("すべての正誤記録とブックマークが削除されます。")
            }
            .alert("リセットしました", isPresented: $resetDone) {
                Button("OK") {}
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
