import BackgroundTasks
import Foundation
import WidgetKit

/// Periodic background work: sample the interface counters (so history survives reboots and
/// 32-bit counter wraps) and auto-resume tracking after another VPN was turned off.
enum BackgroundRefresh {
    static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "com.example.datatracker") + ".refresh"
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("DataTracker: could not schedule refresh: \(error)")
        }
    }

    @MainActor
    static func run() async {
        schedule()
        DeviceSampler.sample()
        await AppModel.shared.vpn.resumeIfNeeded()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
