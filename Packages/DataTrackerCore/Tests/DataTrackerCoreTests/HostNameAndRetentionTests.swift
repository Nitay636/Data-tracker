import XCTest
@testable import DataTrackerCore

final class HostNameAndRetentionTests: XCTestCase {
    /// Response for www.youtube.com: CNAME youtube-ui.l.google.com, then A 142.250.1.1 and A 142.250.1.2.
    static func youtubeResponse() -> [UInt8] {
        func name(_ s: String) -> [UInt8] {
            s.split(separator: ".").flatMap { [UInt8($0.utf8.count)] + Array($0.utf8) } + [0]
        }
        var b: [UInt8] = [0x12, 0x34, 0x81, 0x80, 0, 1, 0, 3, 0, 0, 0, 0]
        b += name("www.youtube.com") + [0, 1, 0, 1]
        let cname = name("youtube-ui.l.google.com")
        b += [0xC0, 12, 0, 5, 0, 1, 0, 0, 0, 60, 0, UInt8(cname.count)] + cname
        b += [0xC0, 45, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 142, 250, 1, 1]
        b += [0xC0, 45, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 142, 250, 1, 2]
        return b
    }

    func testParsesQuestionNameAndAddresses() {
        let answer = DNSResponseParser.parse(Self.youtubeResponse())
        XCTAssertEqual(answer?.name, "www.youtube.com")
        XCTAssertEqual(answer?.addresses, ["142.250.1.1", "142.250.1.2"])
    }

    func testIgnoresQueriesAndGarbage() {
        var query = Self.youtubeResponse()
        query[2] = 0x01 // not a response
        XCTAssertNil(DNSResponseParser.parse(query))
        XCTAssertNil(DNSResponseParser.parse([1, 2, 3]))
        XCTAssertNil(DNSResponseParser.parse(Array(Self.youtubeResponse().prefix(30))))
    }

    func testCacheMapsAddressesToNormalizedNames() {
        let cache = HostNameCache()
        cache.record(DNSResponseParser.parse(Self.youtubeResponse())!)
        XCTAssertEqual(cache.name(for: "142.250.1.2"), "youtube.com")
        cache.record(host: "10.0.0.1", for: "1.1.1.1")
        XCTAssertNil(cache.name(for: "1.1.1.1"))
    }

    func testTunnelConfigHasNoMappedDNS() {
        XCTAssertFalse(TunnelConfiguration.yaml(socksPort: 1).contains("mapdns"))
    }

    func testRetentionCutoff() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 15))!
        XCTAssertNil(RetentionPeriod.forever.cutoff(now: now, calendar: calendar))
        XCTAssertEqual(RetentionPeriod.threeMonths.cutoff(now: now, calendar: calendar),
                       calendar.date(from: DateComponents(year: 2026, month: 2, day: 20)))
    }

    func testDeleteHistoryKeepsRecentDataAndAssignments() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("u.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try UsageStore(url: url)
        let old: Int64 = 1000, recent: Int64 = 2000
        try store.addInterfaceUsage([old: [.wifi: ByteCount(received: 1)], recent: [.wifi: ByteCount(received: 2)]])
        try store.addDomainUsage([DomainUsageKey(hour: old, domain: "a.com", kind: .wifi): ByteCount(received: 1),
                                  DomainUsageKey(hour: recent, domain: "a.com", kind: .wifi): ByteCount(received: 2)])
        _ = try store.beginSession(at: Hour.start(of: old))
        try store.setMapping(domain: "a.com", target: .custom("A"))

        try store.deleteHistory(before: Hour.start(of: 1500))
        XCTAssertEqual(try store.interfaceUsage(fromHour: 0, toHour: 5000).map(\.hour), [recent])
        XCTAssertEqual(try store.domainUsage(fromHour: 0, toHour: 5000).map(\.hour), [recent])
        XCTAssertTrue(try store.sessions(overlapping: .distantPast, .distantFuture).isEmpty)
        XCTAssertEqual(try store.mappings().count, 1)
        store.compact()
    }
}
