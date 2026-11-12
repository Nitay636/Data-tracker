import SwiftUI
import WidgetKit
import DataTrackerCore

struct UsageEntryTimeline: TimelineEntry {
    let date: Date
    let totals: NetworkBytes
    let topApps: [UsageEntry]
    let trackingCoverage: Double

    static let placeholder = UsageEntryTimeline(
        date: Date(),
        totals: NetworkBytes(wifi: ByteCount(received: 1_800_000_000, sent: 120_000_000),
                             cellular: ByteCount(received: 420_000_000, sent: 40_000_000)),
        topApps: [
            UsageEntry(id: .app("youtube"), info: AppResolver.info(for: .app("youtube")),
                       bytes: NetworkBytes(wifi: ByteCount(received: 900_000_000), cellular: ByteCount(received: 120_000_000))),
            UsageEntry(id: .app("instagram"), info: AppResolver.info(for: .app("instagram")),
                       bytes: NetworkBytes(wifi: ByteCount(received: 300_000_000), cellular: ByteCount(received: 150_000_000))),
            UsageEntry(id: .app("spotify"), info: AppResolver.info(for: .app("spotify")),
                       bytes: NetworkBytes(cellular: ByteCount(received: 90_000_000)))
        ],
        trackingCoverage: 1)
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntryTimeline { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntryTimeline) -> Void) {
        completion(context.isPreview ? .placeholder : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntryTimeline>) -> Void) {
        let entry = load()
        // Each refresh also samples the counters, which keeps history accurate when the app isn't opened.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func load() -> UsageEntryTimeline {
        let now = Date()
        guard let store = SharedStore.open() else {
            return UsageEntryTimeline(date: now, totals: .zero, topApps: [], trackingCoverage: 0)
        }
        DeviceSampler.sample(into: store, now: now)
        let period = AppGroup.settings.periodCalculator.period(.day, offset: 0, now: now)
        do {
            let report = UsageReportBuilder(resolver: AppResolver(customMappings: try store.mappings()))
                .build(period: period, now: now,
                       interfaceRows: try store.interfaceUsage(fromHour: period.startHour, toHour: period.endHour),
                       domainRows: try store.domainUsage(fromHour: period.startHour, toHour: period.endHour),
                       sessions: try store.sessions(overlapping: period.start, period.end))
            let apps = report.entries.filter { $0.id != .untracked && $0.id != .hotspot }
            return UsageEntryTimeline(date: now, totals: report.totals, topApps: Array(apps.prefix(3)),
                                      trackingCoverage: report.trackedShare)
        } catch {
            return UsageEntryTimeline(date: now, totals: .zero, topApps: [], trackingCoverage: 0)
        }
    }
}

struct DataTrackerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntryTimeline

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(entry.totals.total.bytesText)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)
            networkLine(symbol: "wifi", color: .wifiColor, value: entry.totals.wifi.total)
            networkLine(symbol: "antenna.radiowaves.left.and.right", color: .cellularColor, value: entry.totals.cellular.total)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text("Top apps").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if entry.topApps.isEmpty {
                    Text(entry.trackingCoverage > 0 ? "No app usage yet" : "Turn on per-app tracking in the app")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(entry.topApps) { app in
                    HStack(spacing: 8) {
                        EntryIcon(info: app.info, size: 22)
                        Text(app.info.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(app.bytes.total.bytesText).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func networkLine(symbol: String, color: Color, value: Int64) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 18)
            Text(value.bytesText).font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

@main
struct DataTrackerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DataTrackerToday", provider: UsageProvider()) { entry in
            DataTrackerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Data")
        .description("Wi-Fi and cellular usage today, and the top apps.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
