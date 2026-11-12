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

    public var periodCalculator: PeriodCalculator {
        PeriodCalculator(calendar: .current, monthMode: monthMode, billingDay: billingDay)
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
    /// DNS server answered by hev-socks5-tunnel itself, so connections carry host names.
    public static let dnsAddress = "198.18.0.2"
    /// Fake addresses handed out by the mapped DNS; they are translated back to host names.
    public static let mappedNetwork = "198.19.0.0"
    public static let mappedNetmask = "255.255.0.0"
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
        mapdns:
          address: \(dnsAddress)
          port: 53
          network: \(mappedNetwork)
          netmask: \(mappedNetmask)
          cache-size: 10000
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
