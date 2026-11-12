import Foundation

public enum PeriodKind: String, CaseIterable, Identifiable, Sendable {
    case day, week, month

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

/// What "month" means in the Month view.
public enum MonthMode: String, CaseIterable, Identifiable, Sendable {
    /// From the carrier plan's reset day to the day before the next reset.
    case billingCycle
    /// The last 30 days.
    case rolling30
    /// From the 1st of the month.
    case calendarMonth

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .billingCycle: return "Billing cycle"
        case .rolling30: return "Last 30 days"
        case .calendarMonth: return "Calendar month"
        }
    }
}

public enum Granularity: Sendable, Equatable {
    case hour, day
}

/// A concrete range of time shown on screen.
public struct UsagePeriod: Equatable, Sendable {
    public var kind: PeriodKind
    public var start: Date
    /// Exclusive.
    public var end: Date
    public var granularity: Granularity

    public init(kind: PeriodKind, start: Date, end: Date, granularity: Granularity) {
        self.kind = kind
        self.start = start
        self.end = end
        self.granularity = granularity
    }

    public var startHour: Int64 { Hour.index(of: start) }
    /// Exclusive.
    public var endHour: Int64 { Hour.index(of: end.addingTimeInterval(3599.999)) }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// Start dates of the chart bars (hours for a day, days otherwise).
    public func bucketStarts(calendar: Calendar) -> [Date] {
        let component: Calendar.Component = granularity == .hour ? .hour : .day
        var result: [Date] = []
        var cursor = start
        while cursor < end, result.count < 1000 {
            result.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return result
    }
}

public struct PeriodCalculator: Sendable {
    public var calendar: Calendar
    public var monthMode: MonthMode
    /// Day of the month the plan resets on (1...31). Short months use their last day.
    public var billingDay: Int

    public init(calendar: Calendar = .current, monthMode: MonthMode = .billingCycle, billingDay: Int = 1) {
        self.calendar = calendar
        self.monthMode = monthMode
        self.billingDay = min(max(billingDay, 1), 31)
    }

    /// - Parameter offset: 0 for the period containing `now`, -1 for the previous one, and so on.
    public func period(_ kind: PeriodKind, offset: Int, now: Date) -> UsagePeriod {
        let today = calendar.startOfDay(for: now)
        switch kind {
        case .day:
            let start = calendar.date(byAdding: .day, value: offset, to: today)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return UsagePeriod(kind: .day, start: start, end: end, granularity: .hour)

        case .week:
            // Rolling 7 days ending today.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
            let end = calendar.date(byAdding: .day, value: 7 * offset, to: tomorrow)!
            let start = calendar.date(byAdding: .day, value: -7, to: end)!
            return UsagePeriod(kind: .week, start: start, end: end, granularity: .day)

        case .month:
            switch monthMode {
            case .rolling30:
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
                let end = calendar.date(byAdding: .day, value: 30 * offset, to: tomorrow)!
                let start = calendar.date(byAdding: .day, value: -30, to: end)!
                return UsagePeriod(kind: .month, start: start, end: end, granularity: .day)

            case .calendarMonth:
                let thisMonth = monthStart(of: now)
                let start = calendar.date(byAdding: .month, value: offset, to: thisMonth)!
                let end = calendar.date(byAdding: .month, value: 1, to: start)!
                return UsagePeriod(kind: .month, start: start, end: end, granularity: .day)

            case .billingCycle:
                let current = billingCycleStart(containing: now)
                let month = calendar.date(byAdding: .month, value: offset, to: monthStart(of: current))!
                let start = cycleStart(inMonthOf: month)
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: month)!
                let end = cycleStart(inMonthOf: nextMonth)
                return UsagePeriod(kind: .month, start: start, end: end, granularity: .day)
            }
        }
    }

    /// Start of the billing cycle that contains `date`.
    public func billingCycleStart(containing date: Date) -> Date {
        let month = monthStart(of: date)
        let candidate = cycleStart(inMonthOf: month)
        if candidate <= date { return candidate }
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: month)!
        return cycleStart(inMonthOf: previousMonth)
    }

    private func monthStart(of date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components)!
    }

    private func cycleStart(inMonthOf monthStart: Date) -> Date {
        let days = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        let day = min(billingDay, days)
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
    }

    /// Human readable title, e.g. "Today", "Mar 3 – Mar 9".
    public func title(for period: UsagePeriod, now: Date) -> String {
        let lastDay = calendar.date(byAdding: .second, value: -1, to: period.end)!
        switch period.kind {
        case .day:
            if calendar.isDate(period.start, inSameDayAs: now) { return "Today" }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
               calendar.isDate(period.start, inSameDayAs: yesterday) { return "Yesterday" }
            return period.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            return rangeTitle(period.start, lastDay)
        case .month:
            if monthMode == .calendarMonth {
                return period.start.formatted(.dateTime.month(.wide).year())
            }
            return rangeTitle(period.start, lastDay)
        }
    }

    private func rangeTitle(_ first: Date, _ last: Date) -> String {
        let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
            && calendar.component(.year, from: last) == calendar.component(.year, from: Date())
        let style: Date.FormatStyle = sameYear
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year()
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }
}
