import SwiftUI
import SwiftData

#if os(macOS)
/// 1ウィンドウで完結するアプリなので、最後のウィンドウを閉じたら終了する
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif

@main
struct AgnoriaApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var model: AppModel

    init() {
        let stores: AgnoriaSchema.Result
        do {
            stores = try AgnoriaSchema.make(cloudSync: AgnoriaSchema.cloudSyncRequested())
        } catch {
            fatalError("SwiftData の初期化に失敗: \(error)")
        }
        ReminderScheduler.shared.activate()
        // 問題データは同梱 JSON をメモリに読む（§2.1 [v1.9]）。読めなければ空のままホームで知らせる
        var catalog = QuestionCatalog.empty
        var catalogError: String?
        do {
            catalog = QuestionCatalog(try BundleData.load())
        } catch {
            catalogError = String(describing: error)
        }
        _model = State(initialValue: AppModel(container: stores.container, settings: AppSettings(), cloudSync: stores.cloudSync,
                                              catalog: catalog, catalogError: catalogError))
    }

    var body: some Scene {
        #if os(macOS)
        // 1ウィンドウのアプリなので WindowGroup ではなく Window（File > New Window が付かない）
        Window("Agnoria", id: "main") {
            content
                .frame(minWidth: 480, minHeight: 640)
        }
        .modelContainer(model.container)
        .defaultSize(width: 560, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            // テキスト編集も独自ツールバー設定もヘルプ文書も無いので、既定メニューから外す
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .help) {}
        }
        #else
        WindowGroup {
            content
        }
        .modelContainer(model.container)
        #endif
    }

    private var content: some View {
        RootView()
            .environment(model)
            .environment(model.settings)
            .task {
                model.prepareAtLaunch()

                #if DEBUG
                model.showDebugStageClearIfRequested()
                model.crashIfRequested()
                #endif
            }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .quiz: QuizView()
                    case .stageClear: StageClearView()
                    case .result: ResultView()
                    case .stats: StatsView()

                    }
                }
        }
    }
}
