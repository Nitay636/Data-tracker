import Foundation

/// Settings shared by the app, the tunnel extension and the widget through the App Group's defaults.
public struct SharedSettings: @unchecked Sendable {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private enum Key {
        static let monthMode = "monthMode"
        static let billingDay = "billingDay"
        static let autoResume = "autoResumeAfterOtherVPN"
        static let wantsTracking = "wantsTracking"
        static let lastPauseDetected = "lastPauseDetected"
        static let lastAutoResume = "lastAutoResume"
        static let retention = "retention"
        static let lastPrune = "lastPrune"
        static let lastTunnelError = "lastTunnelError"
    }

    public var monthMode: MonthMode {
        get { defaults.string(forKey: Key.monthMode).flatMap(MonthMode.init(rawValue:)) ?? .billingCycle }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.monthMode) }
    }

    public var billingDay: Int {
        get {
            let value = defaults.integer(forKey: Key.billingDay)
            return value == 0 ? 1 : min(max(value, 1), 31)
        }
        nonmutating set { defaults.set(min(max(newValue, 1), 31), forKey: Key.billingDay) }
    }

    /// Turn the tracking VPN back on automatically once another VPN disconnects.
    public var autoResumeAfterOtherVPN: Bool {
        get { defaults.object(forKey: Key.autoResume) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.autoResume) }
    }

    /// The user's own choice. Stays `true` while iOS pauses us for another VPN, and becomes `false`
    /// only when the user turns tracking off in this app.
    public var wantsTracking: Bool {
        get { defaults.bool(forKey: Key.wantsTracking) }
        nonmutating set { defaults.set(newValue, forKey: Key.wantsTracking) }
    }

    public var lastAutoResume: Date? {
        get { defaults.object(forKey: Key.lastAutoResume) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastAutoResume) }
    }

    public var retention: RetentionPeriod {
        get { defaults.string(forKey: Key.retention).flatMap(RetentionPeriod.init(rawValue:)) ?? .forever }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.retention) }
    }

    /// Why the tracking VPN last failed, written by the tunnel extension.
    public var lastTunnelError: String? {
        get { defaults.string(forKey: Key.lastTunnelError) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastTunnelError) }
    }

    public var lastPrune: Date? {
        get { defaults.object(forKey: Key.lastPrune) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastPrune) }
    }

    public var periodCalculator: PeriodCalculator {
        PeriodCalculator(calendar: .current, monthMode: monthMode, billingDay: billingDay)
    }
}

/// How long usage history is kept on the phone.
public enum RetentionPeriod: String, CaseIterable, Identifiable, Sendable {
    case oneMonth, threeMonths, sixMonths, oneYear, twoYears, forever

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneMonth: return "1 month"
        case .threeMonths: return "3 months"
        case .sixMonths: return "6 months"
        case .oneYear: return "1 year"
        case .twoYears: return "2 years"
        case .forever: return "Forever"
        }
    }

    /// Oldest date to keep, or `nil` to keep everything.
    public func cutoff(now: Date, calendar: Calendar = .current) -> Date? {
        let months: Int
        switch self {
        case .oneMonth: months = 1
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .oneYear: months = 12
        case .twoYears: months = 24
        case .forever: return nil
        }
        return calendar.date(byAdding: .month, value: -months, to: calendar.startOfDay(for: now))
    }
}

/// Messages the app sends to the running tunnel extension.
public enum TunnelMessage {
    /// Write buffered per-domain counts to the database now.
    public static let flush = Data("flush".utf8)
}

/// Configuration for hev-socks5-tunnel inside the packet tunnel extension.
public enum TunnelConfiguration {
    public static let tunnelAddress = "198.18.0.1"
    public static let tunnelSubnetMask = "255.255.0.0"
    public static let tunnelIPv6Address = "fd64:7472:6b00::1"
    public static let mtu = 8500

    public static func yaml(socksPort: UInt16) -> String {
        """
        tunnel:
          mtu: \(mtu)
        socks5:
          port: \(socksPort)
          address: 127.0.0.1
          udp: 'tcp'
        misc:
          task-stack-size: 24576
          tcp-buffer-size: 16384
          max-session-count: 1200
          connect-timeout: 10000
          tcp-read-write-timeout: 300000
          udp-read-write-timeout: 60000
          log-file: stderr
          log-level: warn
        """
    }
}

public enum ByteFormatter {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func string(_ bytes: ByteCount) -> String {
        string(bytes.total)
    }
}
