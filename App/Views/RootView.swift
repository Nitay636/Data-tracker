import SwiftUI
import DataTrackerCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Usage", systemImage: "chart.bar.fill", value: 0) {
                UsageView(showAllApps: { selectedTab = 1 })
            }
            Tab("Apps", systemImage: "square.grid.2x2.fill", value: 1) {
                AppsView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                SettingsView()
            }
        }
        .task {
            await model.vpn.load()
            model.reload()
        }
        .task(id: scenePhase) {
            // Keep the numbers fresh while the app is open.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                model.reload(flush: true)
            }
        }
    }
}

struct UsageView: View {
    @Environment(AppModel.self) private var model
    var showAllApps: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PeriodHeader()
                }
                if let report = model.report {
                    Section {
                        NetworkTotalsView(bytes: report.totals, hotspot: report.hotspot)
                    }
                    Section("Usage over time") {
                        UsageChart(buckets: report.buckets, granularity: report.period.granularity, periodKind: report.period.kind)
                    }
                    Section {
                        TrackingStatusBanner()
                    }
                    topApps(report)
                } else if let error = model.loadError {
                    ContentUnavailableView("Couldn't load usage", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Data Usage")
            .navigationDestination(for: EntryID.self) { id in
                EntryDetailView(id: id)
            }
            .refreshable { model.reload(flush: true) }
        }
    }

    @ViewBuilder
    private func topApps(_ report: UsageReport) -> some View {
        let top = Array(report.entries.prefix(5))
        Section {
            if top.isEmpty {
                Text("No usage recorded for this period yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(top) { entry in
                NavigationLink(value: entry.id) {
                    EntryRow(entry: entry, filter: .all, maximum: top.first?.bytes.total ?? 1)
                }
            }
            if report.entries.count > top.count {
                Button("See all \(report.entries.count) apps", action: showAllApps)
            }
        } header: {
            Text("Top apps")
        } footer: {
            if report.trackedShare < 0.999 && report.trackedShare > 0 {
                Text("Per-app tracking covered \(Int((report.trackedShare * 100).rounded()))% of this period. The rest is under “Not tracked”.")
            }
        }
    }
}

struct AppsView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    PeriodHeader()
                    Picker("Network", selection: $model.filter) {
                        ForEach(NetworkFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let report = model.report {
                    let entries = sortedEntries(report)
                    Section {
                        if entries.isEmpty {
                            Text(searchText.isEmpty ? "No usage on this network for this period." : "No matches.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(entries) { entry in
                            NavigationLink(value: entry.id) {
                                EntryRow(entry: entry, filter: model.filter, maximum: model.filter.value(entries.first?.bytes ?? .zero))
                            }
                        }
                    } footer: {
                        Text("Per-app numbers come from the on-device VPN and are estimates. “iOS & System Services” includes traffic iOS sends outside VPNs.")
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Apps")
            .searchable(text: $searchText, prompt: "Search apps and domains")
            .navigationDestination(for: EntryID.self) { id in
                EntryDetailView(id: id)
            }
            .refreshable { model.reload(flush: true) }
        }
    }

    private func sortedEntries(_ report: UsageReport) -> [UsageEntry] {
        report.entries
            .filter { model.filter.value($0.bytes) > 0 }
            .filter { searchText.isEmpty || $0.info.name.localizedCaseInsensitiveContains(searchText)
                || report.domains(for: $0.id).contains { $0.domain.localizedCaseInsensitiveContains(searchText) } }
            .sorted { model.filter.value($0.bytes) > model.filter.value($1.bytes) }
    }
}
