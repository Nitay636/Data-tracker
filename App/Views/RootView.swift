import SwiftUI
import DataTrackerCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        @Bindable var model = model
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
        .sensoryFeedback(.selection, trigger: selectedTab)
        .fullScreenCover(isPresented: $model.showOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $model.showRatingPrompt) {
            RatingPromptView()
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
                model.reload(flush: true, quiet: true)
            }
        }
    }
}

/// Small spinner in the navigation bar while a reload the user started is running.
struct LoadingToolbar: ToolbarContent {
    let isLoading: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isLoading { ProgressView() }
        }
    }
}

struct UsageView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("order.topApps") private var order = ListOrder()
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
            .toolbar { LoadingToolbar(isLoading: model.isLoading) }
            .navigationDestination(for: EntryID.self) { id in
                EntryDetailView(id: id)
            }
            .refreshable { model.reload(flush: true, quiet: true) }
        }
    }

    @ViewBuilder
    private func topApps(_ report: UsageReport) -> some View {
        // The five biggest, then ordered the way the user chose.
        let top = order.sorted(Array(report.entries.prefix(5)), amount: { $0.bytes.total }, date: { $0.lastUsed })
        Section {
            if top.isEmpty {
                Text("No usage yet")
                    .foregroundStyle(.secondary)
            } else {
                ListOrderRow(order: $order)
            }
            ForEach(top) { entry in
                NavigationLink(value: entry.id) {
                    EntryRow(entry: entry, filter: .all, maximum: top.map(\.bytes.total).max() ?? 1)
                }
            }
            if report.entries.count > top.count {
                Button("See all \(report.entries.count) apps", action: showAllApps)
            }
        } header: {
            Text("Top apps")
        }
    }
}

struct AppsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("order.apps") private var order = ListOrder()
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var keyboardUp = false

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
                    .sensoryFeedback(.selection, trigger: model.filter)
                    ListOrderRow(order: $order)
                }
                if let report = model.report {
                    let entries = sortedEntries(report)
                    let maximum = entries.map { model.filter.value($0.bytes) }.max() ?? 1
                    Section {
                        if entries.isEmpty {
                            Text(searchText.isEmpty ? "No usage" : "No matches")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(entries) { entry in
                            NavigationLink(value: entry.id) {
                                EntryRow(entry: entry, filter: model.filter, maximum: maximum)
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Apps")
            .toolbar { LoadingToolbar(isLoading: model.isLoading) }
            .searchable(text: $searchText, prompt: "Search")
            .searchFocused($searchFocused)
            .onChange(of: searchFocused) { _, focused in keyboardUp = focused }
            .onChange(of: keyboardUp) { _, up in if !up { searchFocused = false } }
            .keyboardFirstSwipe($keyboardUp)
            .navigationDestination(for: EntryID.self) { id in
                EntryDetailView(id: id)
            }
            .refreshable { model.reload(flush: true, quiet: true) }
        }
    }

    private func sortedEntries(_ report: UsageReport) -> [UsageEntry] {
        let matching = report.entries
            .filter { model.filter.value($0.bytes) > 0 }
            .filter { searchText.isEmpty || $0.info.name.localizedCaseInsensitiveContains(searchText)
                || report.domains(for: $0.id).contains { $0.domain.localizedCaseInsensitiveContains(searchText) } }
        return order.sorted(matching, amount: { model.filter.value($0.bytes) }, date: { $0.lastUsed })
    }
}
