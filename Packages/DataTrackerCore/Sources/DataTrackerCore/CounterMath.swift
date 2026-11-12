import Foundation

/// The last value seen for one network interface's byte counters.
public struct CounterSnapshot: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64
    /// Device boot time (seconds since 1970). Counters restart from zero after a reboot.
    public var bootTime: TimeInterval
    /// When the reading was taken (seconds since 1970).
    public var timestamp: TimeInterval
    /// `true` when the values come from 64-bit counters, `false` for 32-bit counters that wrap at 4 GiB.
    public var isWide: Bool

    public init(received: UInt64, sent: UInt64, bootTime: TimeInterval, timestamp: TimeInterval, isWide: Bool) {
        self.received = received
        self.sent = sent
        self.bootTime = bootTime
        self.timestamp = timestamp
        self.isWide = isWide
    }
}

public enum CounterMath {
    /// A 32-bit counter that was above this value and is now lower is treated as having wrapped
    /// rather than reset.
    public static let wrapThreshold: UInt64 = 0xC000_0000
    /// Boot times that differ by more than this are a reboot (boot time jitters slightly when the clock is adjusted).
    public static let rebootTolerance: TimeInterval = 30

    public struct Delta: Equatable, Sendable {
        public var bytes: ByteCount
        /// Start of the interval the bytes were used in.
        public var intervalStart: TimeInterval
        public var intervalEnd: TimeInterval
    }

    /// Computes how many bytes were used since `previous`. Returns `nil` when there is no
    /// previous reading (the first reading only establishes a baseline).
    public static func delta(previous: CounterSnapshot?, current: CounterSnapshot) -> Delta? {
        guard let previous else { return nil }

        if abs(current.bootTime - previous.bootTime) > rebootTolerance {
            // Rebooted: everything counted since boot is new usage.
            let start = max(current.bootTime, previous.timestamp)
            return Delta(bytes: ByteCount(received: clampInt64(current.received), sent: clampInt64(current.sent)),
                         intervalStart: start,
                         intervalEnd: max(current.timestamp, start))
        }

        let wide = previous.isWide && current.isWide
        let oldRx = wide ? previous.received : truncate(previous.received)
        let oldTx = wide ? previous.sent : truncate(previous.sent)
        let newRx = wide ? current.received : truncate(current.received)
        let newTx = wide ? current.sent : truncate(current.sent)

        let rx = difference(old: oldRx, new: newRx, wide: wide)
        let tx = difference(old: oldTx, new: newTx, wide: wide)
        return Delta(bytes: ByteCount(received: clampInt64(rx), sent: clampInt64(tx)),
                     intervalStart: previous.timestamp,
                     intervalEnd: max(current.timestamp, previous.timestamp))
    }

    static func difference(old: UInt64, new: UInt64, wide: Bool) -> UInt64 {
        if new >= old { return new - old }
        if !wide && old >= wrapThreshold {
            // 32-bit counter wrapped past 4 GiB.
            return new + (UInt64(UInt32.max) + 1) - old
        }
        // Counter was reset (interface re-created).
        return new
    }

    private static func truncate(_ value: UInt64) -> UInt64 {
        value & UInt64(UInt32.max)
    }

    private static func clampInt64(_ value: UInt64) -> Int64 {
        value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }
}

/// Spreads usage measured over an interval across the hours it covers, in proportion to time.
public enum HourSpreader {
    /// Intervals longer than this are shortened to their last `maximumSpan` seconds.
    public static let maximumSpan: TimeInterval = 14 * 24 * 3600

    public static func spread(_ bytes: ByteCount, from start: TimeInterval, to end: TimeInterval) -> [Int64: ByteCount] {
        guard !bytes.isZero else { return [:] }
        let endDate = Date(timeIntervalSince1970: end)
        let clampedStart = max(start, end - maximumSpan)
        let duration = end - clampedStart
        guard duration >= 1 else {
            return [Hour.index(of: endDate): bytes]
        }

        let firstHour = Hour.index(of: Date(timeIntervalSince1970: clampedStart))
        // An interval that ends exactly on an hour boundary does not touch the next hour.
        let lastHour = Hour.index(of: Date(timeIntervalSince1970: end - 0.000_001))
        if firstHour == lastHour {
            return [firstHour: bytes]
        }

        var result: [Int64: ByteCount] = [:]
        var assigned = ByteCount.zero
        for hour in firstHour...lastHour {
            let hourStart = TimeInterval(hour) * 3600
            let overlap = min(end, hourStart + 3600) - max(clampedStart, hourStart)
            if hour == lastHour {
                result[hour, default: .zero] += bytes - assigned
            } else if overlap > 0 {
                let share = bytes.scaled(by: overlap / duration)
                result[hour, default: .zero] += share
                assigned += share
            }
        }
        return result.filter { !$0.value.isZero }
    }
}

/// Maps iOS interface names to counter kinds.
public enum InterfaceClassifier {
    public static func kind(forInterface name: String) -> CounterKind? {
        if name.hasPrefix("pdp_ip") { return .cellular }
        // en0 is Wi-Fi; other en* interfaces are wired adapters, which we count with Wi-Fi.
        if name.hasPrefix("en") { return .wifi }
        // Personal Hotspot clients are bridged through bridge100.
        if name.hasPrefix("bridge") { return .hotspot }
        // lo0, utun*/ipsec* (VPN tunnels, would double count), awdl0/llw0 (AirDrop), ap1 (part of the bridge), etc.
        return nil
    }
}
