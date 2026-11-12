import XCTest
@testable import DataTrackerCore

final class PeriodCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testDayIsCalendarDayWithHourlyBuckets() {
        let calc = PeriodCalculator(calendar: calendar)
        let p = calc.period(.day, offset: 0, now: date(2026, 3, 10, 15))
        XCTAssertEqual(p.start, date(2026, 3, 10, 0))
        XCTAssertEqual(p.end, date(2026, 3, 11, 0))
        XCTAssertEqual(p.granularity, .hour)
        XCTAssertEqual(p.bucketStarts(calendar: calendar).count, 24)
    }

    func testPreviousDay() {
        let calc = PeriodCalculator(calendar: calendar)
        let p = calc.period(.day, offset: -1, now: date(2026, 3, 10))
        XCTAssertEqual(p.start, date(2026, 3, 9, 0))
    }

    func testWeekIsLastSevenDaysIncludingToday() {
        let calc = PeriodCalculator(calendar: calendar)
        let p = calc.period(.week, offset: 0, now: date(2026, 3, 10))
        XCTAssertEqual(p.start, date(2026, 3, 4, 0))
        XCTAssertEqual(p.end, date(2026, 3, 11, 0))
        XCTAssertEqual(p.bucketStarts(calendar: calendar).count, 7)
        let previous = calc.period(.week, offset: -1, now: date(2026, 3, 10))
        XCTAssertEqual(previous.end, p.start)
    }

    func testCalendarMonth() {
        let calc = PeriodCalculator(calendar: calendar, monthMode: .calendarMonth)
        let p = calc.period(.month, offset: 0, now: date(2026, 2, 20))
        XCTAssertEqual(p.start, date(2026, 2, 1, 0))
        XCTAssertEqual(p.end, date(2026, 3, 1, 0))
        XCTAssertEqual(p.bucketStarts(calendar: calendar).count, 28)
    }

    func testRolling30() {
        let calc = PeriodCalculator(calendar: calendar, monthMode: .rolling30)
        let p = calc.period(.month, offset: 0, now: date(2026, 3, 30))
        XCTAssertEqual(p.end, date(2026, 3, 31, 0))
        XCTAssertEqual(p.start, date(2026, 3, 1, 0))
    }

    func testBillingCycleBeforeAndAfterResetDay() {
        let calc = PeriodCalculator(calendar: calendar, monthMode: .billingCycle, billingDay: 15)
        let before = calc.period(.month, offset: 0, now: date(2026, 3, 10))
        XCTAssertEqual(before.start, date(2026, 2, 15, 0))
        XCTAssertEqual(before.end, date(2026, 3, 15, 0))

        let after = calc.period(.month, offset: 0, now: date(2026, 3, 15, 1))
        XCTAssertEqual(after.start, date(2026, 3, 15, 0))
        XCTAssertEqual(after.end, date(2026, 4, 15, 0))

        let previous = calc.period(.month, offset: -1, now: date(2026, 3, 15, 1))
        XCTAssertEqual(previous.start, date(2026, 2, 15, 0))
    }

    func testBillingDay31InShortMonthsUsesLastDay() {
        let calc = PeriodCalculator(calendar: calendar, monthMode: .billingCycle, billingDay: 31)
        let p = calc.period(.month, offset: 0, now: date(2026, 3, 5))
        XCTAssertEqual(p.start, date(2026, 2, 28, 0))
        XCTAssertEqual(p.end, date(2026, 3, 31, 0))
    }

    func testDSTDayHas23HourlyBuckets() {
        // US clocks moved forward on 2026-03-08.
        let calc = PeriodCalculator(calendar: calendar)
        let p = calc.period(.day, offset: 0, now: date(2026, 3, 8, 12))
        XCTAssertEqual(p.bucketStarts(calendar: calendar).count, 23)
    }
}
