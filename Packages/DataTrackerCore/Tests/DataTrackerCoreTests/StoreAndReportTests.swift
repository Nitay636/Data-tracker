import XCTest
@testable import DataTrackerCore

final class StoreAndReportTests: XCTestCase {
    private var directory: URL!
    private var store: UsageStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try UsageStore(url: directory.appendingPathComponent("usage.sqlite"))
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private let hour: Int64 = 490_000 // some hour in 2025
    private var hourStart: Date { Hour.start(of: hour) }

    func testUpsertsAccumulate() throws {
        try store.addInterfaceUsage([hour: [.wifi: ByteCount(received: 10, sent: 1)]])
        try store.addInterfaceUsage([hour: [.wifi: ByteCount(received: 5, sent: 2)], hour + 1: [.cellular: ByteCount(received: 7, sent: 0)]])
        let rows = try store.interfaceUsage(fromHour: hour, toHour: hour + 2).sorted { $0.hour < $1.hour }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].bytes, ByteCount(received: 15, sent: 3))
        XCTAssertEqual(rows[1].kind, .cellular)

        let key = DomainUsageKey(hour: hour, domain: "netflix.com", kind: .wifi)
        try store.addDomainUsage([key: ByteCount(received: 100, sent: 10)])
        try store.addDomainUsage([key: ByteCount(received: 100, sent: 10)])
        XCTAssertEqual(try store.domainUsage(fromHour: hour, toHour: hour + 1).first?.bytes, ByteCount(received: 200, sent: 20))
    }

    func testRecorderBaselineThenDelta() throws {
        let boot: TimeInterval = hourStart.timeIntervalSince1970 - 10_000
        let t0 = hourStart.addingTimeInterval(60)
        try UsageRecorder.record(readings: [
            InterfaceReading(name: "en0", received: 1_000, sent: 100, isWide: true),
            InterfaceReading(name: "utun4", received: 5, sent: 5, isWide: true)
        ], bootTime: boot, now: t0, into: store)
        XCTAssertTrue(try store.interfaceUsage(fromHour: hour, toHour: hour + 1).isEmpty)

        try UsageRecorder.record(readings: [
            InterfaceReading(name: "en0", received: 6_000, sent: 600, isWide: true),
            InterfaceReading(name: "pdp_ip0", received: 50, sent: 5, isWide: true)
        ], bootTime: boot, now: t0.addingTimeInterval(600), into: store)
        let rows = try store.interfaceUsage(fromHour: hour, toHour: hour + 1)
        XCTAssertEqual(rows, [InterfaceUsageRow(hour: hour, kind: .wifi, bytes: ByteCount(received: 5_000, sent: 500))])
        XCTAssertEqual(try store.counterStates().keys.sorted(), ["en0", "pdp_ip0"])
    }

    func testRecorderIgnoresOlderReadingFromAnotherProcess() throws {
        let boot: TimeInterval = 1
        let t = hourStart.addingTimeInterval(100)
        try UsageRecorder.record(readings: [InterfaceReading(name: "en0", received: 100, sent: 0, isWide: true)], bootTime: boot, now: t, into: store)
        try UsageRecorder.record(readings: [InterfaceReading(name: "en0", received: 900, sent: 0, isWide: true)], bootTime: boot, now: t.addingTimeInterval(100), into: store)
        try UsageRecorder.record(readings: [InterfaceReading(name: "en0", received: 500, sent: 0, isWide: true)], bootTime: boot, now: t.addingTimeInterval(50), into: store)
        XCTAssertEqual(try store.interfaceUsage(fromHour: hour, toHour: hour + 1).first?.bytes.received, 800)
    }

    func testSessionsAndMappings() throws {
        let id = try store.beginSession(at: hourStart)
        try store.extendSession(id, to: hourStart.addingTimeInterval(1800))
        let sessions = try store.sessions(overlapping: hourStart, hourStart.addingTimeInterval(3600))
        XCTAssertEqual(sessions.first?.end, hourStart.addingTimeInterval(1800))

        try store.setMapping(domain: "example.org", target: .custom("Bank"))
        XCTAssertEqual(try store.mappings(), ["example.org": "custom:Bank"])
        try store.setMapping(domain: "example.org", target: nil)
        XCTAssertTrue(try store.mappings().isEmpty)
    }

    func testReportAttributesTunnelSystemHotspotAndUntracked() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let period = UsagePeriod(kind: .day, start: hourStart, end: hourStart.addingTimeInterval(86_400), granularity: .hour)
        let now = hourStart.addingTimeInterval(3 * 3600)

        let interfaceRows = [
            // Hour 0: fully tracked.
            InterfaceUsageRow(hour: hour, kind: .wifi, bytes: ByteCount(received: 1_000, sent: 100)),
            InterfaceUsageRow(hour: hour, kind: .cellular, bytes: ByteCount(received: 500, sent: 50)),
            InterfaceUsageRow(hour: hour, kind: .hotspot, bytes: ByteCount(received: 200, sent: 20)),
            // Hour 1: half tracked.
            InterfaceUsageRow(hour: hour + 1, kind: .wifi, bytes: ByteCount(received: 400, sent: 0))
        ]
        let domainRows = [
            DomainUsageRow(hour: hour, domain: "googlevideo.com", kind: .wifi, bytes: ByteCount(received: 800, sent: 80)),
            DomainUsageRow(hour: hour, domain: "netflix.com", kind: .cellular, bytes: ByteCount(received: 250, sent: 25)),
            DomainUsageRow(hour: hour, domain: "unknown-site.org", kind: .wifi, bytes: ByteCount(received: 100, sent: 0))
        ]
        let sessions = [TrackingSession(id: 1, start: hourStart, end: hourStart.addingTimeInterval(3600 + 1800))]

        let report = UsageReportBuilder(resolver: AppResolver(), calendar: calendar)
            .build(period: period, now: now, interfaceRows: interfaceRows, domainRows: domainRows, sessions: sessions)

        XCTAssertEqual(report.totals.wifi, ByteCount(received: 1_400, sent: 100))
        XCTAssertEqual(report.totals.cellular, ByteCount(received: 500, sent: 50))
        XCTAssertEqual(report.hotspot, ByteCount(received: 200, sent: 20))
        XCTAssertEqual(report.buckets.count, 24)
        XCTAssertEqual(report.buckets[0].bytes.wifi.received, 1_000)
        XCTAssertEqual(report.buckets[1].bytes.wifi.received, 400)

        XCTAssertEqual(report.entry(for: .app("youtube"))?.bytes.wifi, ByteCount(received: 800, sent: 80))
        XCTAssertEqual(report.entry(for: .app("netflix"))?.bytes.cellular, ByteCount(received: 250, sent: 25))
        XCTAssertEqual(report.entry(for: .domain("unknown-site.org"))?.bytes.total, 100)
        XCTAssertEqual(report.entry(for: .hotspot)?.bytes.cellular, ByteCount(received: 200, sent: 20))

        // System = residual while tracked: hour 0 wifi 100/20, cellular 500-250-200=50 / 50-25-20=5; hour 1 half of 400.
        let system = report.entry(for: .app(AppCatalog.systemID))
        XCTAssertEqual(system?.bytes.wifi, ByteCount(received: 300, sent: 20))
        XCTAssertEqual(system?.bytes.cellular, ByteCount(received: 50, sent: 5))
        XCTAssertEqual(report.entry(for: .untracked)?.bytes.wifi, ByteCount(received: 200, sent: 0))

        // Everything adds up to the interface totals.
        let sum = report.entries.reduce(NetworkBytes.zero) { $0 + $1.bytes }
        XCTAssertEqual(sum, report.totals)

        XCTAssertEqual(report.entries.first?.id, .app("youtube"))
        XCTAssertEqual(report.series(for: .app("youtube"))[0].bytes.wifi.received, 800)
        XCTAssertEqual(report.domains(for: .app(AppCatalog.systemID)).first?.domain, UsageReport.outsideVPNLabel)
        XCTAssertEqual(report.trackedShare, 1.5 / 3, accuracy: 0.001)
    }
}
