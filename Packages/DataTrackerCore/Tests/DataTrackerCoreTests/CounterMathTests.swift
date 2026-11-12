import XCTest
@testable import DataTrackerCore

final class CounterMathTests: XCTestCase {
    private func snap(_ rx: UInt64, _ tx: UInt64, boot: TimeInterval = 1000, ts: TimeInterval, wide: Bool = true) -> CounterSnapshot {
        CounterSnapshot(received: rx, sent: tx, bootTime: boot, timestamp: ts, isWide: wide)
    }

    func testFirstReadingIsBaseline() {
        XCTAssertNil(CounterMath.delta(previous: nil, current: snap(500, 100, ts: 2000)))
    }

    func testNormalIncrease() {
        let d = CounterMath.delta(previous: snap(1000, 200, ts: 2000), current: snap(1500, 260, ts: 2600))
        XCTAssertEqual(d?.bytes, ByteCount(received: 500, sent: 60))
        XCTAssertEqual(d?.intervalStart, 2000)
        XCTAssertEqual(d?.intervalEnd, 2600)
    }

    func testRebootCountsEverythingSinceBoot() {
        let d = CounterMath.delta(previous: snap(9_000_000, 1_000, boot: 1000, ts: 5000),
                                  current: snap(4_000, 300, boot: 8000, ts: 9000))
        XCTAssertEqual(d?.bytes, ByteCount(received: 4_000, sent: 300))
        XCTAssertEqual(d?.intervalStart, 8000)
    }

    func testThirtyTwoBitWrap() {
        let old: UInt64 = 0xFFFF_FF00
        let d = CounterMath.delta(previous: snap(old, 10, ts: 1, wide: false), current: snap(0x100, 20, ts: 2, wide: false))
        XCTAssertEqual(d?.bytes.received, 0x200)
        XCTAssertEqual(d?.bytes.sent, 10)
    }

    func testCounterResetWithoutWrap() {
        let d = CounterMath.delta(previous: snap(50_000, 10, ts: 1, wide: false), current: snap(700, 20, ts: 2, wide: false))
        XCTAssertEqual(d?.bytes.received, 700)
    }

    func testSwitchingFromWideToNarrowUsesLow32Bits() {
        let wideValue: UInt64 = (5 << 32) | 1_000
        let d = CounterMath.delta(previous: snap(wideValue, 0, ts: 1, wide: true),
                                  current: snap(1_500, 0, ts: 2, wide: false))
        XCTAssertEqual(d?.bytes.received, 500)
    }

    func testSpreadWithinOneHour() {
        let hourStart: TimeInterval = 3600 * 100
        let result = HourSpreader.spread(ByteCount(received: 100, sent: 0), from: hourStart + 60, to: hourStart + 600)
        XCTAssertEqual(result, [100: ByteCount(received: 100, sent: 0)])
    }

    func testSpreadAcrossHoursConservesTotal() {
        let start: TimeInterval = 3600 * 100 + 1800 // half way into hour 100
        let end: TimeInterval = 3600 * 102 // end of hour 101
        let result = HourSpreader.spread(ByteCount(received: 999, sent: 3), from: start, to: end)
        XCTAssertEqual(Set(result.keys), [100, 101])
        XCTAssertEqual(result[100]?.received, 333)
        XCTAssertEqual(result.values.reduce(ByteCount.zero, +), ByteCount(received: 999, sent: 3))
    }

    func testInterfaceClassification() {
        XCTAssertEqual(InterfaceClassifier.kind(forInterface: "en0"), .wifi)
        XCTAssertEqual(InterfaceClassifier.kind(forInterface: "pdp_ip0"), .cellular)
        XCTAssertEqual(InterfaceClassifier.kind(forInterface: "pdp_ip1"), .cellular)
        XCTAssertEqual(InterfaceClassifier.kind(forInterface: "bridge100"), .hotspot)
        XCTAssertNil(InterfaceClassifier.kind(forInterface: "utun3"))
        XCTAssertNil(InterfaceClassifier.kind(forInterface: "lo0"))
        XCTAssertNil(InterfaceClassifier.kind(forInterface: "awdl0"))
    }
}
