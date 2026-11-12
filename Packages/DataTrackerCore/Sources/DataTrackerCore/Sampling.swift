import Foundation

/// One interface's cumulative counters as read from the system.
public struct InterfaceReading: Equatable, Sendable {
    public var name: String
    public var received: UInt64
    public var sent: UInt64
    public var isWide: Bool

    public init(name: String, received: UInt64, sent: UInt64, isWide: Bool) {
        self.name = name
        self.received = received
        self.sent = sent
        self.isWide = isWide
    }
}

/// Converts cumulative interface counters into hourly usage.
public enum UsageRecorder {
    /// Compares `readings` with the last stored readings, adds the difference to the hourly totals,
    /// and stores the new readings. Safe to call from several processes at once.
    @discardableResult
    public static func record(readings: [InterfaceReading], bootTime: TimeInterval, now: Date,
                              into store: UsageStore) throws -> [Int64: [CounterKind: ByteCount]] {
        try store.transaction { () throws -> [Int64: [CounterKind: ByteCount]] in
            let previous = try store.counterStates()
            var hourly: [Int64: [CounterKind: ByteCount]] = [:]
            let timestamp = now.timeIntervalSince1970

            for reading in readings {
                guard let kind = InterfaceClassifier.kind(forInterface: reading.name) else { continue }
                let current = CounterSnapshot(received: reading.received, sent: reading.sent,
                                              bootTime: bootTime, timestamp: timestamp, isWide: reading.isWide)
                if let old = previous[reading.name], old.timestamp > timestamp {
                    // Another process already stored a newer reading; skip to avoid double counting.
                    continue
                }
                if let delta = CounterMath.delta(previous: previous[reading.name], current: current) {
                    for (hour, bytes) in HourSpreader.spread(delta.bytes, from: delta.intervalStart, to: delta.intervalEnd) {
                        hourly[hour, default: [:]][kind, default: .zero] += bytes
                    }
                }
                try store.setCounterState(current, for: reading.name)
            }
            try store.addInterfaceUsage(hourly)
            return hourly
        }
    }
}

/// Thread-safe in-memory accumulator used by the tunnel extension between database writes.
public final class DomainTrafficAccumulator: @unchecked Sendable {
    private var values: [DomainUsageKey: ByteCount] = [:]
    private let lock = NSLock()

    public init() {}

    public func add(domain: String, kind: NetworkKind, received: Int, sent: Int, at date: Date = Date()) {
        guard received > 0 || sent > 0 else { return }
        let key = DomainUsageKey(hour: Hour.index(of: date), domain: domain, kind: kind)
        lock.lock()
        values[key, default: .zero] += ByteCount(received: Int64(received), sent: Int64(sent))
        lock.unlock()
    }

    /// Returns everything accumulated so far and clears it.
    public func drain() -> [DomainUsageKey: ByteCount] {
        lock.lock()
        defer { lock.unlock() }
        let result = values
        values.removeAll(keepingCapacity: true)
        return result
    }

    /// Puts values back, e.g. after a failed write.
    public func restore(_ drained: [DomainUsageKey: ByteCount]) {
        lock.lock()
        for (key, bytes) in drained { values[key, default: .zero] += bytes }
        lock.unlock()
    }
}
