import Foundation

public struct UsageBucket: Identifiable, Equatable, Sendable {
    public var start: Date
    public var bytes: NetworkBytes
    public var id: Date { start }

    public init(start: Date, bytes: NetworkBytes) {
        self.start = start
        self.bytes = bytes
    }
}

public struct UsageEntry: Identifiable, Hashable, Sendable {
    public var id: EntryID
    public var info: EntryInfo
    public var bytes: NetworkBytes

    public init(id: EntryID, info: EntryInfo, bytes: NetworkBytes) {
        self.id = id
        self.info = info
        self.bytes = bytes
    }
}

public struct DomainBreakdown: Identifiable, Hashable, Sendable {
    public var domain: String
    public var bytes: NetworkBytes
    /// `true` for rows that are not real domains (e.g. traffic that bypassed the VPN).
    public var isSynthetic: Bool
    public var id: String { domain }
}

/// Everything shown for one period: totals, chart buckets, and the ranked app list.
public struct UsageReport: Sendable {
    /// Domain label used for system traffic that iOS sends outside the VPN.
    public static let outsideVPNLabel = "Traffic outside the VPN"

    public let period: UsagePeriod
    public let generatedAt: Date
    /// Measured on the network interfaces. Cellular includes Personal Hotspot.
    public let totals: NetworkBytes
    public let hotspot: ByteCount
    public let buckets: [UsageBucket]
    /// Sorted by total usage, largest first.
    public let entries: [UsageEntry]
    /// Share of the elapsed part of the period during which the tracking VPN was running (0...1).
    public let trackedShare: Double

    let bucketStarts: [Date]
    let entryHourly: [EntryID: [Int64: NetworkBytes]]
    let entryDomains: [EntryID: [String: NetworkBytes]]

    public func entry(for id: EntryID) -> UsageEntry? {
        entries.first { $0.id == id }
    }

    /// Chart buckets for one entry, using the same granularity as the period.
    public func series(for id: EntryID) -> [UsageBucket] {
        UsageReportBuilder.bucketize(entryHourly[id] ?? [:], starts: bucketStarts, periodEnd: period.end)
    }

    public func domains(for id: EntryID) -> [DomainBreakdown] {
        (entryDomains[id] ?? [:])
            .map { DomainBreakdown(domain: $0.key, bytes: $0.value, isSynthetic: $0.key == Self.outsideVPNLabel) }
            .filter { !$0.bytes.isZero }
            .sorted { $0.bytes.total > $1.bytes.total }
    }
}

public struct UsageReportBuilder: Sendable {
    public var resolver: AppResolver
    public var calendar: Calendar

    public init(resolver: AppResolver, calendar: Calendar = .current) {
        self.resolver = resolver
        self.calendar = calendar
    }

    public func build(period: UsagePeriod, now: Date,
                      interfaceRows: [InterfaceUsageRow],
                      domainRows: [DomainUsageRow],
                      sessions: [TrackingSession]) -> UsageReport {
        let startHour = period.startHour
        let endHour = period.endHour

        // 1. Physical interface usage per hour.
        var physical: [Int64: NetworkBytes] = [:]
        var hotspotHourly: [Int64: ByteCount] = [:]
        for row in interfaceRows where row.hour >= startHour && row.hour < endHour {
            switch row.kind {
            case .wifi: physical[row.hour, default: .zero].wifi += row.bytes
            case .cellular: physical[row.hour, default: .zero].cellular += row.bytes
            case .hotspot: hotspotHourly[row.hour, default: .zero] += row.bytes
            }
        }

        // 2. Traffic seen by the tunnel, attributed to apps.
        var tunneled: [Int64: NetworkBytes] = [:]
        var entryHourly: [EntryID: [Int64: NetworkBytes]] = [:]
        var entryDomains: [EntryID: [String: NetworkBytes]] = [:]
        var resolved: [String: EntryID] = [:]
        for row in domainRows where row.hour >= startHour && row.hour < endHour {
            let id: EntryID
            if let cached = resolved[row.domain] {
                id = cached
            } else {
                id = resolver.resolve(domain: row.domain)
                resolved[row.domain] = id
            }
            tunneled[row.hour, default: .zero][row.kind] += row.bytes
            entryHourly[id, default: [:]][row.hour, default: .zero][row.kind] += row.bytes
            entryDomains[id, default: [:]][row.domain, default: .zero][row.kind] += row.bytes
        }

        // 3. What the interfaces saw but the tunnel did not: system traffic iOS keeps outside VPNs,
        //    or everything when tracking was off.
        let systemID = EntryID.app(AppCatalog.systemID)
        for (hour, bytes) in physical {
            let tunnel = tunneled[hour] ?? .zero
            let hotspot = hotspotHourly[hour] ?? .zero
            let residual = NetworkBytes(
                wifi: (bytes.wifi - tunnel.wifi).clampedToZero,
                cellular: (bytes.cellular - tunnel.cellular - hotspot).clampedToZero)
            guard !residual.isZero else { continue }

            let fraction = trackedFraction(hour: hour, sessions: sessions, now: now)
            let tracked = NetworkBytes(wifi: residual.wifi.scaled(by: fraction),
                                       cellular: residual.cellular.scaled(by: fraction))
            let untracked = NetworkBytes(wifi: residual.wifi - tracked.wifi,
                                         cellular: residual.cellular - tracked.cellular)
            if !tracked.isZero {
                entryHourly[systemID, default: [:]][hour, default: .zero] += tracked
                entryDomains[systemID, default: [:]][UsageReport.outsideVPNLabel, default: .zero] += tracked
            }
            if !untracked.isZero {
                entryHourly[.untracked, default: [:]][hour, default: .zero] += untracked
            }
        }
        for (hour, bytes) in hotspotHourly where !bytes.isZero {
            entryHourly[.hotspot, default: [:]][hour, default: .zero].cellular += bytes
        }

        // 4. Totals, chart and ranking.
        let totals = physical.values.reduce(NetworkBytes.zero, +)
        let hotspot = hotspotHourly.values.reduce(ByteCount.zero, +)
        let starts = period.bucketStarts(calendar: calendar)
        let buckets = Self.bucketize(physical, starts: starts, periodEnd: period.end)

        let entries = entryHourly.compactMap { id, hours -> UsageEntry? in
            let sum = hours.values.reduce(NetworkBytes.zero, +)
            guard !sum.isZero else { return nil }
            return UsageEntry(id: id, info: AppResolver.info(for: id), bytes: sum)
        }
        .sorted { lhs, rhs in
            if lhs.bytes.total != rhs.bytes.total { return lhs.bytes.total > rhs.bytes.total }
            return lhs.info.name < rhs.info.name
        }

        return UsageReport(period: period, generatedAt: now, totals: totals, hotspot: hotspot,
                           buckets: buckets, entries: entries,
                           trackedShare: trackedShare(period: period, sessions: sessions, now: now),
                           bucketStarts: starts, entryHourly: entryHourly, entryDomains: entryDomains)
    }

    // MARK: Helpers

    /// A heartbeat this close to `now` means the session is still running.
    static let liveSessionTolerance: TimeInterval = 120

    private func effectiveEnd(_ session: TrackingSession, now: Date) -> Date {
        now.timeIntervalSince(session.end) <= Self.liveSessionTolerance ? max(session.end, now) : session.end
    }

    /// Fraction of the (elapsed part of the) hour covered by tracking sessions.
    func trackedFraction(hour: Int64, sessions: [TrackingSession], now: Date) -> Double {
        let start = Hour.start(of: hour)
        let end = min(Hour.start(of: hour + 1), max(now, start.addingTimeInterval(1)))
        return coverage(from: start, to: end, sessions: sessions, now: now)
    }

    func trackedShare(period: UsagePeriod, sessions: [TrackingSession], now: Date) -> Double {
        let end = min(period.end, now)
        guard end > period.start else { return 0 }
        return coverage(from: period.start, to: end, sessions: sessions, now: now)
    }

    private func coverage(from start: Date, to end: Date, sessions: [TrackingSession], now: Date) -> Double {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        var covered: TimeInterval = 0
        var cursor = start
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            let sessionStart = max(session.start, cursor)
            let sessionEnd = min(effectiveEnd(session, now: now), end)
            if sessionEnd > sessionStart {
                covered += sessionEnd.timeIntervalSince(sessionStart)
                cursor = sessionEnd
            }
        }
        return min(1, max(0, covered / length))
    }

    static func bucketize(_ hourly: [Int64: NetworkBytes], starts: [Date], periodEnd: Date) -> [UsageBucket] {
        var buckets = starts.map { UsageBucket(start: $0, bytes: .zero) }
        guard !buckets.isEmpty else { return [] }
        for (hour, bytes) in hourly {
            let date = Hour.start(of: hour)
            guard date >= starts[0], date < periodEnd else { continue }
            // Last bucket whose start is <= date.
            var low = 0
            var high = starts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if starts[mid] <= date { low = mid } else { high = mid - 1 }
            }
            buckets[low].bytes += bytes
        }
        return buckets
    }
}
