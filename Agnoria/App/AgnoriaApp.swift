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
        let container: ModelContainer
        do {
            container = try AgnoriaSchema.makeContainer()
        } catch {
            fatalError("SwiftData の初期化に失敗: \(error)")
        }
        _model = State(initialValue: AppModel(container: container, settings: AppSettings()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
                .task { await model.importBundledDataIfNeeded() }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 640)
                #endif
        }
        .modelContainer(model.container)
        #if os(macOS)
        .defaultSize(width: 560, height: 820)
        .windowResizability(.contentMinSize)
        #endif
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
                    case .result: ResultView()
                    }
                }
        }
    }
}
