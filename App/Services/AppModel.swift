import Foundation
import Observation
import WidgetKit
import DataTrackerCore

enum NetworkFilter: String, CaseIterable, Identifiable {
    case all, wifi, cellular

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        }
    }

    func value(_ bytes: NetworkBytes) -> Int64 {
        switch self {
        case .all: return bytes.total
        case .wifi: return bytes.wifi.total
        case .cellular: return bytes.cellular.total
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let vpn = TrackingVPNController()

    private(set) var periodKind: PeriodKind = .day
    private(set) var offset = 0
    private(set) var monthMode: MonthMode
    private(set) var billingDay: Int
    private(set) var report: UsageReport?
    private(set) var mappings: [String: String] = [:]
    private(set) var loadError: String?
    private(set) var autoResume: Bool
    var filter: NetworkFilter = .all

    @ObservationIgnored private let settings = AppGroup.settings
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init() {
        monthMode = settings.monthMode
        billingDay = settings.billingDay
        autoResume = settings.autoResumeAfterOtherVPN
    }

    // MARK: Period

    var calculator: PeriodCalculator {
        PeriodCalculator(calendar: .current, monthMode: monthMode, billingDay: billingDay)
    }

    var period: UsagePeriod { calculator.period(periodKind, offset: offset, now: Date()) }
    var periodTitle: String { calculator.title(for: period, now: Date()) }

    func select(_ kind: PeriodKind) {
        guard kind != periodKind else { return }
        periodKind = kind
        offset = 0
        reload()
    }

    func shift(by delta: Int) {
        offset = min(0, offset + delta)
        reload()
    }

    func setMonthMode(_ mode: MonthMode) {
        monthMode = mode
        settings.monthMode = mode
        offset = 0
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setBillingDay(_ day: Int) {
        billingDay = min(max(day, 1), 31)
        settings.billingDay = billingDay
        reload()
    }

    func setAutoResume(_ enabled: Bool) {
        autoResume = enabled
        settings.autoResumeAfterOtherVPN = enabled
        if enabled {
            Task { await vpn.resumeIfNeeded() }
        }
    }

    // MARK: Data

    /// Reloads the report. With `flush`, the tunnel writes its buffered counts first.
    func reload(flush: Bool = false) {
        reloadTask?.cancel()
        let period = self.period
        reloadTask = Task { [weak self] in
            guard let self else { return }
            if flush { await self.vpn.flush() }
            let result = await Task.detached(priority: .userInitiated) {
                Self.buildReport(period: period)
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let (report, mappings)):
                self.report = report
                self.mappings = mappings
                self.loadError = nil
            case .failure(let error):
                self.loadError = String(describing: error)
            }
        }
    }

    private nonisolated static func buildReport(period: UsagePeriod) -> Result<(UsageReport, [String: String]), Error> {
        guard let store = SharedStore.open() else {
            return .failure(NSError(domain: "DataTracker", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "The usage database could not be opened."]))
        }
        DeviceSampler.sample(into: store)
        do {
            let mappings = try store.mappings()
            let interfaceRows = try store.interfaceUsage(fromHour: period.startHour, toHour: period.endHour)
            let domainRows = try store.domainUsage(fromHour: period.startHour, toHour: period.endHour)
            let sessions = try store.sessions(overlapping: period.start, period.end)
            let builder = UsageReportBuilder(resolver: AppResolver(customMappings: mappings))
            let report = builder.build(period: period, now: Date(), interfaceRows: interfaceRows,
                                       domainRows: domainRows, sessions: sessions)
            return .success((report, mappings))
        } catch {
            return .failure(error)
        }
    }

    // MARK: Domain assignments

    func assign(domain: String, to target: EntryID?) {
        do {
            try SharedStore.open()?.setMapping(domain: domain, target: target)
        } catch {
            loadError = String(describing: error)
        }
        reload()
    }

    func assignment(for domain: String) -> EntryID? {
        mappings[domain].flatMap(EntryID.init(key:))
    }

    /// Names of apps the user created.
    var customAppNames: [String] {
        let names = mappings.values.compactMap { key -> String? in
            if case .custom(let name)? = EntryID(key: key) { return name }
            return nil
        }
        return Array(Set(names)).sorted()
    }

    var databaseSize: Int64 { SharedStore.open()?.fileSize() ?? 0 }
}
