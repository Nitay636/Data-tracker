import XCTest
@testable import DataTrackerCore

final class DomainTests: XCTestCase {
    func testNormalization() {
        XCTAssertEqual(DomainNormalizer.normalize("r4---sn-ab5l6nzr.googlevideo.com"), "googlevideo.com")
        XCTAssertEqual(DomainNormalizer.normalize("WWW.Netflix.COM."), "netflix.com")
        XCTAssertEqual(DomainNormalizer.normalize("news.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(DomainNormalizer.normalize("a.b.mail.google.com"), "mail.google.com")
        XCTAssertEqual(DomainNormalizer.normalize("p52-caldav.icloud.com"), "p52-caldav.icloud.com")
        XCTAssertEqual(DomainNormalizer.normalize("x.com"), "x.com")
        XCTAssertEqual(DomainNormalizer.normalize("17.253.144.10"), "17.253.144.10")
        XCTAssertEqual(DomainNormalizer.normalize("[2001:db8::1]"), "2001:db8::1")
    }

    func testIPDetection() {
        XCTAssertTrue(DomainNormalizer.isIPAddress("8.8.8.8"))
        XCTAssertTrue(DomainNormalizer.isIPAddress("2a03:2880:f12f:83:face:b00c::25de"))
        XCTAssertFalse(DomainNormalizer.isIPAddress("1.2.3"))
        XCTAssertFalse(DomainNormalizer.isIPAddress("cafe.com"))
        XCTAssertFalse(DomainNormalizer.isIPAddress("300.1.1.1"))
    }

    func testCatalogResolution() {
        let resolver = AppResolver()
        XCTAssertEqual(resolver.resolve(domain: "googlevideo.com"), .app("youtube"))
        XCTAssertEqual(resolver.resolve(domain: "mail.google.com"), .app("gmail"))
        XCTAssertEqual(resolver.resolve(domain: "www.google.com"), .app("google"))
        XCTAssertEqual(resolver.resolve(domain: "itunes.apple.com"), .app("apple.appstore"))
        XCTAssertEqual(resolver.resolve(domain: "gsp-ssl.apple.com"), .app(AppCatalog.systemID))
        XCTAssertEqual(resolver.resolve(domain: "p52-caldav.icloud.com"), .app("apple.icloud"))
        XCTAssertEqual(resolver.resolve(domain: "cdninstagram.com"), .app("instagram"))
        XCTAssertEqual(resolver.resolve(domain: "example.org"), .domain("example.org"))
        XCTAssertEqual(resolver.resolve(domain: "10.0.0.1"), .unidentified)
    }

    func testCustomMappingsWin() {
        let resolver = AppResolver(customMappings: [
            "example.org": EntryID.custom("My Bank").key,
            "googlevideo.com": EntryID.app("google").key
        ])
        XCTAssertEqual(resolver.resolve(domain: "example.org"), .custom("My Bank"))
        XCTAssertEqual(resolver.resolve(domain: "googlevideo.com"), .app("google"))
    }

    func testCatalogHasUniqueIDs() {
        XCTAssertEqual(Set(AppCatalog.all.map(\.id)).count, AppCatalog.all.count)
        XCTAssertGreaterThanOrEqual(AppCatalog.all.count, 100)
    }

    func testEntryIDKeyRoundTrip() {
        let ids: [EntryID] = [.app("youtube"), .custom("A:B"), .domain("x.org"), .unidentified, .hotspot, .untracked]
        for id in ids { XCTAssertEqual(EntryID(key: id.key), id) }
    }
}
