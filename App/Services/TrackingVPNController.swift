import Foundation
import NetworkExtension
import Observation
import DataTrackerCore

/// Detects whether some VPN (not necessarily ours) is up, from the system proxy configuration,
/// which lists one scoped entry per active network interface.
enum VPNDetector {
    static func isAnyVPNActive() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = settings["__SCOPED__"] as? [String: Any] else { return false }
        let prefixes = ["utun", "ipsec", "ppp", "tap", "tun"]
        return scoped.keys.contains { key in prefixes.contains { key.hasPrefix($0) } }
    }
}

/// Installs, starts, stops and auto-resumes the on-device tracking VPN.
@MainActor
@Observable
final class TrackingVPNController {
    enum Phase: Equatable {
        case notInstalled
        case off
        case connecting
        case on
        case disconnecting
        /// The user wants tracking but iOS switched to another VPN (or the VPN was turned off in Settings).
        case paused
    }

    private(set) var status: NEVPNStatus = .invalid
    private(set) var isInstalled = false
    private(set) var isEnabledInSettings = false
    private(set) var otherVPNActive = false
    private(set) var isBusy = false
    var lastError: String?

    @ObservationIgnored private var manager: NETunnelProviderManager?
    @ObservationIgnored private var statusObserver: NSObjectProtocol?
    @ObservationIgnored private let settings = AppGroup.settings

    static var tunnelBundleIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.example.datatracker") + ".tunnel"
    }

    init() {
        statusObserver = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    var phase: Phase {
        guard isInstalled else { return .notInstalled }
        switch status {
        case .connected: return .on
        case .connecting, .reasserting: return .connecting
        case .disconnecting: return .disconnecting
        default: return settings.wantsTracking ? .paused : .off
        }
    }

    var wantsTracking: Bool { settings.wantsTracking }

    func load() async {
        do {
            manager = try await NETunnelProviderManager.loadAllFromPreferences().first
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    func refreshStatus() {
        isInstalled = manager != nil
        status = manager?.connection.status ?? .invalid
        isEnabledInSettings = manager?.isEnabled ?? false
        otherVPNActive = status != .connected && VPNDetector.isAnyVPNActive()
    }

    /// User turned tracking on. Installs the VPN configuration the first time (iOS asks for permission).
    func turnOn() async {
        isBusy = true
        defer { isBusy = false }
        settings.wantsTracking = true
        lastError = nil
        do {
            let manager = try await prepareManager()
            try manager.connection.startVPNTunnel()
        } catch {
            lastError = Self.describe(error)
        }
        refreshStatus()
    }

    /// User turned tracking off. On-demand is disabled so iOS doesn't reconnect it.
    func turnOff() async {
        isBusy = true
        defer { isBusy = false }
        settings.wantsTracking = false
        if let manager {
            manager.isOnDemandEnabled = false
            do { try await manager.saveToPreferences() } catch { lastError = Self.describe(error) }
            manager.connection.stopVPNTunnel()
        }
        refreshStatus()
    }

    /// Turns tracking back on after another VPN was used, if the user allowed that in Settings.
    /// Called when the app becomes active, from background refresh, and from the widget's refresh.
    @discardableResult
    func resumeIfNeeded() async -> Bool {
        guard settings.wantsTracking, settings.autoResumeAfterOtherVPN else { return false }
        await load()
        guard let manager else { return false }
        switch manager.connection.status {
        case .connected, .connecting, .reasserting, .disconnecting:
            return false
        default:
            break
        }
        // Never kick out a VPN that is still connected; wait until it is turned off.
        guard !VPNDetector.isAnyVPNActive() else {
            refreshStatus()
            return false
        }
        do {
            let prepared = try await prepareManager()
            try prepared.connection.startVPNTunnel()
            settings.lastAutoResume = Date()
            refreshStatus()
            return true
        } catch {
            lastError = Self.describe(error)
            refreshStatus()
            return false
        }
    }

    /// Asks the running tunnel to write its buffered counts so the screen is up to date.
    func flush() async {
        guard let session = manager?.connection as? NETunnelProviderSession, session.status == .connected else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            do {
                try session.sendProviderMessage(TunnelMessage.flush) { _ in once.resume() }
            } catch {
                once.resume()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { once.resume() }
        }
    }

    private func prepareManager() async throws -> NETunnelProviderManager {
        let manager = self.manager ?? NETunnelProviderManager()
        let configuration = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = Self.tunnelBundleIdentifier
        configuration.serverAddress = "On-device only"
        configuration.disconnectOnSleep = false
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "DataTracker (on-device)"
        manager.isEnabled = true

        // Keep it connected (including after reboots and network changes) while it is the active VPN.
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        manager.onDemandRules = [rule]
        manager.isOnDemandEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        self.manager = manager
        return manager
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NEVPNErrorDomain, nsError.code == NEVPNError.configurationReadWriteFailed.rawValue {
            return "iOS didn't allow adding the VPN configuration. Tap Turn On again and choose Allow."
        }
        return error.localizedDescription
    }
}

/// Resumes a continuation at most once (response vs. timeout).
private final class ResumeOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
