import SwiftUI
import WidgetKit

@main
struct DataTrackerApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await model.vpn.load()
                    await model.vpn.resumeIfNeeded()
                    model.reload(flush: true)
                }
            case .background:
                BackgroundRefresh.schedule()
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}
