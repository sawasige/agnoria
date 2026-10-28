import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmReset1 = false
    @State private var confirmReset2 = false
    @State private var resetDone = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// やり直そうとしている軸と帯（確認してからやり直す §4.4 [v2.0] [v2.5]）
    @State private var pendingRestart: (mode: DrillMode, level: Int)?
    @State private var confirmRestart = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    ForEach(DrillMode.allCases, id: \.self) { mode in
                        // 先に進むだけ。戻る・今の帯からやり直すのは下の「やり直す…」から [v2.5]
                        Picker("\(mode.title)の到達帯", selection: Binding(
                            get: { settings.unlockedLevel(mode) },
                            set: { level in
                                guard level > settings.unlockedLevel(mode) else { return }
                                settings.setUnlockedLevel(level, for: mode)
                                model.analytics.log(.settingsChanged(key: "unlockedLevel.\(mode.rawValue)"))
                                model.analytics.syncUserProperties()
                                model.refreshWidgetSnapshot()
                            })) {
                            ForEach(Stage.levels.filter { $0 >= settings.unlockedLevel(mode) }, id: \.self) { Text("\($0) 点帯").tag($0) }
                        }
                    }
                    // やり直し = 軸と帯（450 から今の到達帯まで）を選ぶ。習得が消えるので確認してから §4.4 [v2.5]
                    Menu {
                        ForEach(DrillMode.allCases, id: \.self) { mode in
                            Menu(mode.title) {
                                ForEach(Stage.levels.filter { $0 <= settings.unlockedLevel(mode) }, id: \.self) { level in
                                    Button("\(level) 点帯から") {
                                        pendingRestart = (mode, level)
                                        confirmRestart = true
                                    }
                                }
                            }
                        }
                    } label: {
                        // 行のどこを押しても開くように、行の幅いっぱいにする
                        Text("やり直す…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .accessibilityIdentifier("stageRestartMenu")
                    .confirmationDialog(restartTitle, isPresented: $confirmRestart, titleVisibility: .visible) {
                        Button("やり直す", role: .destructive) {
                            if let r = pendingRestart { model.restartStage(r.mode, from: r.level) }
                            pendingRestart = nil
                        }
                        Button("キャンセル", role: .cancel) { pendingRestart = nil }
                    } message: {
                        if let r = pendingRestart {
                            Text("\(r.level) 点帯以上の\(r.mode.title)の習得をリセットします。回答数・正解数・ブックマークは残ります。")
                        }
                    }
                } header: {
                    Text("ステージ")
                } footer: {
                    Text("単語・文法・リスニングは別々に帯を進みます。おまかせと分野タイルは、それぞれの到達帯までのスコア帯から出題します。帯の習得率が 80% になると自動で次の帯へ進みます。先に進みたいときはここで上げられます。「やり直す」では、選んだ帯以上の習得をリセットして、その帯から学び直せます。")
                }



                Section {
                    Toggle("正解・不正解の効果音", isOn: $settings.soundEffects)
                        .accessibilityIdentifier("soundEffectsToggle")
                    Toggle("回答後に例文を自動で読み上げる", isOn: $settings.autoSpeak)
                        .accessibilityIdentifier("autoSpeakToggle")
                    VStack(alignment: .leading) {
                        Slider(value: $settings.speechRate, in: AppSettings.speechRateRange, step: 0.05) {
                            Text("読み上げの速度")
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
                } header: {
                    Text("音")
                } footer: {
                    Text("速度は例文の読み上げとリスニングの両方に効きます。リスニングは音の出せる場所で（マナーモードでも鳴ります）。")
                }



                Section {
                    Toggle("学習のリマインダー", isOn: Binding(
                        get: { settings.reminderEnabled },
                        set: { on in Task { await setReminder(on) } }))
                    if settings.reminderEnabled {
                        DatePicker("時刻", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                    if notificationStatus == .denied {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("通知が許可されていません")
                                .foregroundStyle(.secondary)
                            Button("通知の設定を開く") { openURL(Self.notificationSettingsURL) }
                        }
                    }
                } header: {
                    Text("リマインダー")
                } footer: {
                    Text("その日まだ 1 セットも終えていなければ、この時刻に通知します。")
                }

                Section {
                    LabeledContent("iCloud 同期", value: cloudSyncLabel)
                } header: {
                    Text("iCloud")
                } footer: {
                    Text(cloudSyncFooter)
                }

                Section {
                    Button("学習履歴をリセット", role: .destructive) { confirmReset1 = true }
                } footer: {
                    Text("正誤の記録・ブックマーク・連続日数が消えます。問題データは残ります。")
                }

                Section("このアプリについて") {
                    LabeledContent("バージョン", value: versionString)
                    Button("App Store でレビューを書く") {
                        model.analytics.log(.reviewLinkOpened)
                        openURL(Self.writeReviewURL)
                    }
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
            .onChange(of: settings.reminderMinutes) {
                model.analytics.log(.settingsChanged(key: "reminderTime"))
                model.refreshReminders()
            }
            .task { notificationStatus = await ReminderScheduler.shared.authorizationStatus() }
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
                Text(model.cloudSync ? "すべての正誤記録とブックマークが削除されます。iCloud に同期した記録も消えます。" : "すべての正誤記録とブックマークが削除されます。")
            }
            .alert("リセットしました", isPresented: $resetDone) {
                Button("OK") {}
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }

    private var restartTitle: String {
        guard let r = pendingRestart else { return "" }
        return "\(r.mode.title)を \(r.level) 点帯からやり直しますか？"
    }

    private var cloudSyncLabel: String {

        switch model.cloudSyncStatus {
        case .syncing: "同期中"
        case .notSignedIn: "未サインイン"
        case .off: "オフ"
        }
    }

    private var cloudSyncFooter: String {
        switch model.cloudSyncStatus {
        case .syncing: "学習の記録は、お使いの iCloud を通じて iPhone・iPad・Mac の間で自動的に同期されます。開発者が見ることはできません。"
        case .notSignedIn: "iCloud にサインインすると、学習の記録が他の端末と自動的に同期されます。"
        case .off: "このビルドでは同期しません。"
        }
    }

    /// トグルでオンにしたとき、まだ決めていなければ OS の許可ダイアログを出す。拒否済みならオンにせず案内を出す
    private func setReminder(_ on: Bool) async {
        if on {
            let status = await ReminderScheduler.shared.authorizationStatus()
            if status == .notDetermined {
                await model.requestReminderPermission()
            } else {
                settings.reminderEnabled = status == .authorized || status == .provisional
            }
        } else {
            settings.reminderEnabled = false
        }
        settings.reminderPrompted = true
        notificationStatus = await ReminderScheduler.shared.authorizationStatus()
        model.analytics.log(.settingsChanged(key: "reminderEnabled"))
        model.refreshReminders()
    }

    /// 時刻のピッカー用。保存は 0 時からの分
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: settings.reminderMinutes,
                                      to: Calendar.current.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.reminderMinutes = (c.hour ?? 20) * 60 + (c.minute ?? 0)
            })
    }

    static var notificationSettingsURL: URL {
        #if os(iOS)
        URL(string: UIApplication.openNotificationSettingsURLString)!
        #else
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.himatsubu.Agnoria")!
        #endif
    }

    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6823061416?action=write-review")!

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
