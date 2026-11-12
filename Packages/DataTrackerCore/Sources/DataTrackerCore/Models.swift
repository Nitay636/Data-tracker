import Foundation

/// The two networks the user cares about.
public enum NetworkKind: Int, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case wifi = 0
    case cellular = 1

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        }
    }
}

/// Interface counters that are recorded per hour.
/// `hotspot` is traffic of devices using this iPhone's Personal Hotspot. It is a *subset* of cellular.
public enum CounterKind: Int, CaseIterable, Sendable, Hashable {
    case wifi = 0
    case cellular = 1
    case hotspot = 2
}

/// Received / sent byte pair.
public struct ByteCount: Equatable, Hashable, Sendable, Codable {
    public var received: Int64
    public var sent: Int64

    public init(received: Int64 = 0, sent: Int64 = 0) {
        self.received = received
        self.sent = sent
    }

    public static let zero = ByteCount()

    public var total: Int64 { received + sent }
    public var isZero: Bool { received == 0 && sent == 0 }

    public static func + (lhs: ByteCount, rhs: ByteCount) -> ByteCount {
        ByteCount(received: lhs.received + rhs.received, sent: lhs.sent + rhs.sent)
    }

    public static func - (lhs: ByteCount, rhs: ByteCount) -> ByteCount {
        ByteCount(received: lhs.received - rhs.received, sent: lhs.sent - rhs.sent)
    }

    public static func += (lhs: inout ByteCount, rhs: ByteCount) {
        lhs = lhs + rhs
    }

    /// Clamps both directions at zero.
    public var clampedToZero: ByteCount {
        ByteCount(received: max(0, received), sent: max(0, sent))
    }

    public func scaled(by factor: Double) -> ByteCount {
        ByteCount(received: Int64((Double(received) * factor).rounded()),
                  sent: Int64((Double(sent) * factor).rounded()))
    }
}

/// Usage split by network.
public struct NetworkBytes: Equatable, Hashable, Sendable {
    public var wifi: ByteCount
    public var cellular: ByteCount

    public init(wifi: ByteCount = .zero, cellular: ByteCount = .zero) {
        self.wifi = wifi
        self.cellular = cellular
    }

    public static let zero = NetworkBytes()

    public var total: Int64 { wifi.total + cellular.total }
    public var isZero: Bool { wifi.isZero && cellular.isZero }

    public subscript(kind: NetworkKind) -> ByteCount {
        get { kind == .wifi ? wifi : cellular }
        set {
            if kind == .wifi { wifi = newValue } else { cellular = newValue }
        }
    }

    public static func + (lhs: NetworkBytes, rhs: NetworkBytes) -> NetworkBytes {
        NetworkBytes(wifi: lhs.wifi + rhs.wifi, cellular: lhs.cellular + rhs.cellular)
    }

    public static func += (lhs: inout NetworkBytes, rhs: NetworkBytes) {
        lhs = lhs + rhs
    }
}

/// Hours are stored as "hours since 1970-01-01 00:00 UTC".
public enum Hour {
    public static func index(of date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / 3600).rounded(.down))
    }

    public static func start(of index: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(index) * 3600)
    }
}

// MARK: - Stored rows

public struct InterfaceUsageRow: Equatable, Sendable {
    public var hour: Int64
    public var kind: CounterKind
    public var bytes: ByteCount

    public init(hour: Int64, kind: CounterKind, bytes: ByteCount) {
        self.hour = hour
        self.kind = kind
        self.bytes = bytes
    }
}

public struct DomainUsageRow: Equatable, Sendable {
    public var hour: Int64
    public var domain: String
    public var kind: NetworkKind
    public var bytes: ByteCount

    public init(hour: Int64, domain: String, kind: NetworkKind, bytes: ByteCount) {
        self.hour = hour
        self.domain = domain
        self.kind = kind
        self.bytes = bytes
    }
}

/// A period of time during which the tracking VPN was running.
public struct TrackingSession: Equatable, Sendable {
    public var id: Int64
    public var start: Date
    public var end: Date

    public init(id: Int64, start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }
}

/// Key used to accumulate per-domain traffic before it is written.
public struct DomainUsageKey: Hashable, Sendable {
    public var hour: Int64
    public var domain: String
    public var kind: NetworkKind

    public init(hour: Int64, domain: String, kind: NetworkKind) {
        self.hour = hour
        self.domain = domain
        self.kind = kind
    }
}
