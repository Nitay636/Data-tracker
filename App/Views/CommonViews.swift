import Charts
import SwiftUI
import DataTrackerCore

/// Day / Week / Month picker plus previous / next navigation. Shared by every screen so the
/// app detail always uses the same view mode as the list it came from.
struct PeriodHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Picker("Period", selection: Binding(get: { model.periodKind }, set: { model.select($0) })) {
                ForEach(PeriodKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    model.shift(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 32)
                }
                .accessibilityLabel("Previous")

                Spacer()
                Text(model.periodTitle)
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()

                Button {
                    model.shift(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 32)
                }
                .disabled(model.offset >= 0)
                .accessibilityLabel("Next")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Stacked Wi-Fi / cellular bars, hourly for a day, daily otherwise. Tap or drag to read a bar.
struct UsageChart: View {
    let buckets: [UsageBucket]
    let granularity: Granularity
    var periodKind: PeriodKind

    @State private var selection: Date?

    private var unit: Calendar.Component { granularity == .hour ? .hour : .day }

    private var xAxisValues: AxisMarkValues {
        switch periodKind {
        case .day: return .stride(by: .hour, count: 6)
        case .week: return .stride(by: .day)
        case .month: return .stride(by: .day, count: 7)
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch periodKind {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.narrow)
        case .month: return .dateTime.day().month(.abbreviated)
        }
    }

    private var selectedBucket: UsageBucket? {
        guard let selection else { return nil }
        return buckets.last { $0.start <= selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            selectionLabel
            Chart {
                ForEach(buckets) { bucket in
                    BarMark(x: .value("Time", bucket.start, unit: unit),
                            y: .value("Data", Double(bucket.bytes.wifi.total)))
                        .foregroundStyle(by: .value("Network", "Wi-Fi"))
                    BarMark(x: .value("Time", bucket.start, unit: unit),
                            y: .value("Data", Double(bucket.bytes.cellular.total)))
                        .foregroundStyle(by: .value("Network", "Cellular"))
                }
                if let selectedBucket {
                    RuleMark(x: .value("Selected", selectedBucket.start, unit: unit))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartForegroundStyleScale(["Wi-Fi": Color.wifiColor, "Cellular": Color.cellularColor])
            .chartXSelection(value: $selection)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) {
                            Text(Int64(bytes).bytesText).font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: xAxisFormat)
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 190)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var selectionLabel: some View {
        if let bucket = selectedBucket {
            HStack(spacing: 12) {
                Text(bucket.start.formatted(granularity == .hour
                                            ? .dateTime.hour().minute()
                                            : .dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .foregroundStyle(.secondary)
                Label(bucket.bytes.wifi.total.bytesText, systemImage: "wifi")
                    .foregroundStyle(Color.wifiColor)
                Label(bucket.bytes.cellular.total.bytesText, systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Color.cellularColor)
            }
            .font(.caption.monospacedDigit())
        } else {
            Text("Tap a bar for details")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Totals for a period or an app: total, Wi-Fi, cellular, with download / upload.
struct NetworkTotalsView: View {
    let bytes: NetworkBytes
    var hotspot: ByteCount? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total").font(.subheadline).foregroundStyle(.secondary)
                Text(bytes.total.bytesText)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            HStack(alignment: .top, spacing: 12) {
                tile(title: "Wi-Fi", symbol: "wifi", color: .wifiColor, value: bytes.wifi)
                tile(title: "Cellular", symbol: "antenna.radiowaves.left.and.right", color: .cellularColor, value: bytes.cellular)
            }
            if let hotspot, !hotspot.isZero {
                Label {
                    Text("Personal Hotspot: \(hotspot.total.bytesText) of cellular")
                } icon: {
                    Image(systemName: "personalhotspot")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func tile(title: String, symbol: String, color: Color, value: ByteCount) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(value.total.bytesText)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text("↓ \(value.received.bytesText)  ↑ \(value.sent.bytesText)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One row in the app ranking.
struct EntryRow: View {
    let entry: UsageEntry
    let filter: NetworkFilter
    let maximum: Int64

    var body: some View {
        HStack(spacing: 12) {
            EntryIcon(info: entry.info)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.info.name)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(filter.value(entry.bytes).bytesText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                SplitBar(bytes: entry.bytes, filter: filter, maximum: maximum)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if !entry.bytes.wifi.isZero { parts.append("Wi-Fi \(entry.bytes.wifi.total.bytesText)") }
        if !entry.bytes.cellular.isZero { parts.append("Cellular \(entry.bytes.cellular.total.bytesText)") }
        return parts.joined(separator: " · ")
    }
}

/// Horizontal bar showing the entry's share, split into Wi-Fi and cellular.
struct SplitBar: View {
    let bytes: NetworkBytes
    let filter: NetworkFilter
    let maximum: Int64

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let scale = maximum > 0 ? width / CGFloat(maximum) : 0
            let wifi = filter == .cellular ? 0 : CGFloat(bytes.wifi.total) * scale
            let cellular = filter == .wifi ? 0 : CGFloat(bytes.cellular.total) * scale
            HStack(spacing: 1) {
                if wifi > 0 { Capsule().fill(Color.wifiColor).frame(width: max(wifi, 2)) }
                if cellular > 0 { Capsule().fill(Color.cellularColor).frame(width: max(cellular, 2)) }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 5)
    }
}

/// Banner shown when per-app tracking isn't running.
struct TrackingStatusBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let vpn = model.vpn
        switch vpn.phase {
        case .on, .connecting, .disconnecting:
            EmptyView()
        case .notInstalled, .off:
            banner(symbol: "eye.slash",
                   title: "Per-app tracking is off",
                   message: "Wi-Fi and cellular totals are still measured. Turn on the on-device VPN to see which apps use data.",
                   button: "Turn On")
        case .paused:
            banner(symbol: "pause.circle",
                   title: vpn.otherVPNActive ? "Paused while another VPN is on" : "Per-app tracking is paused",
                   message: model.autoResume
                       ? "It turns back on automatically after the other VPN disconnects."
                       : "Auto-resume is off in Settings.",
                   button: "Resume Now")
        }
    }

    private func banner(symbol: String, title: String, message: String, button: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button(button) {
                    Task {
                        await model.vpn.turnOn()
                        model.reload()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.vpn.isBusy)
            }
        }
        .padding(.vertical, 4)
    }
}
