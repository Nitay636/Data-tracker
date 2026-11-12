import AppIntents
import WidgetKit

/// Lets the user resume tracking from Shortcuts, Spotlight, Siri, the Action button or a
/// Control Center shortcut — handy right after turning another VPN off.
struct StartTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Per-App Tracking"
    static let description = IntentDescription("Turns on DataTracker's on-device VPN that measures usage per app.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vpn = AppModel.shared.vpn
        await vpn.load()
        await vpn.turnOn()
        WidgetCenter.shared.reloadAllTimelines()
        if let error = vpn.lastError {
            return .result(dialog: "Couldn't start tracking: \(error)")
        }
        return .result(dialog: "Per-app tracking is on.")
    }
}

struct StopTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Per-App Tracking"
    static let description = IntentDescription("Turns off DataTracker's on-device VPN. Wi-Fi and cellular totals keep counting.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vpn = AppModel.shared.vpn
        await vpn.load()
        await vpn.turnOff()
        return .result(dialog: "Per-app tracking is off.")
    }
}

struct DataTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTrackingIntent(),
                    phrases: ["Start tracking in \(.applicationName)", "Resume \(.applicationName)"],
                    shortTitle: "Start Tracking",
                    systemImageName: "play.circle.fill")
        AppShortcut(intent: StopTrackingIntent(),
                    phrases: ["Stop tracking in \(.applicationName)"],
                    shortTitle: "Stop Tracking",
                    systemImageName: "stop.circle.fill")
    }
}
