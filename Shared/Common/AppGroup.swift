import Foundation
import DataTrackerCore

/// Access to the App Group container shared by the app, the tunnel extension and the widget.
enum AppGroup {
    /// Set per target in Info.plist from the `APP_GROUP_ID` build setting.
    static let identifier: String = {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? "group.com.example.datatracker"
    }()

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var databaseURL: URL {
        containerURL.appendingPathComponent("Database", isDirectory: true).appendingPathComponent("usage.sqlite")
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var settings: SharedSettings { SharedSettings(defaults: defaults) }
}

/// One shared database connection per process.
enum SharedStore {
    private static let lock = NSLock()
    private static var cached: UsageStore?

    static func open() -> UsageStore? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        do {
            let store = try UsageStore(url: AppGroup.databaseURL)
            cached = store
            return store
        } catch {
            NSLog("DataTracker: cannot open database: \(error)")
            return nil
        }
    }
}
