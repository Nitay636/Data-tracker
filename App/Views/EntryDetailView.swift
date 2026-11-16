import SwiftUI
import DataTrackerCore

/// Detail for one app: totals, a chart by hour (Day view) or by day (Week / Month view),
/// and the domains that make it up.
struct EntryDetailView: View {
    @Environment(AppModel.self) private var model
    let id: EntryID
    @State private var assigningDomain: AssignTarget?

    var body: some View {
        let info = AppResolver.info(for: id)
        List {
            Section {
                PeriodHeader()
            }
            if let report = model.report {
                let entry = report.entry(for: id)
                Section {
                    HStack(spacing: 14) {
                        EntryIcon(info: info, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.name).font(.title3.weight(.semibold))
                            if let subtitle = info.subtitle {
                                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let share = shareText(entry: entry, report: report) {
                                Text(share).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    NetworkTotalsView(bytes: entry?.bytes ?? .zero)
                }
                Section(report.period.granularity == .hour ? "By hour" : "By day") {
                    UsageChart(buckets: report.series(for: id), granularity: report.period.granularity,
                               periodKind: report.period.kind)
                }
                explanation
                domainsSection(report.domains(for: id))
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $assigningDomain) { target in
            AssignDomainView(domain: target.domain)
        }
    }

    private func shareText(entry: UsageEntry?, report: UsageReport) -> String? {
        guard let entry, report.totals.total > 0 else { return nil }
        let percent = Double(entry.bytes.total) / Double(report.totals.total) * 100
        return percent < 0.1 ? "<0.1% of total" : String(format: "%.1f%% of total", percent)
    }

    @ViewBuilder
    private var explanation: some View {
        if case .domain(let domain) = id {
            Section {
                Button {
                    assigningDomain = AssignTarget(domain: domain)
                } label: {
                    Label("Assign to an app…", systemImage: "arrow.triangle.merge")
                }
            }
        }
    }

    @ViewBuilder
    private func domainsSection(_ domains: [DomainBreakdown]) -> some View {
        if !domains.isEmpty, id != .hotspot, id != .untracked {
            Section {
                ForEach(domains) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.domain)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(detail(item.bytes))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.bytes.total.bytesText)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        if !item.isSynthetic {
                            Button("Assign to Another App…", systemImage: "arrow.triangle.merge") {
                                assigningDomain = AssignTarget(domain: item.domain)
                            }
                            if model.assignment(for: item.domain) != nil {
                                Button("Use Built-in Grouping", systemImage: "arrow.uturn.backward", role: .destructive) {
                                    model.assign(domain: item.domain, to: nil)
                                }
                            }
                        }
                    }
                    .swipeActions {
                        if !item.isSynthetic {
                            Button("Reassign") { assigningDomain = AssignTarget(domain: item.domain) }
                                .tint(.blue)
                        }
                    }
                }
            } header: {
                Text("Domains")
            }
        }
    }

    private func detail(_ bytes: NetworkBytes) -> String {
        var parts: [String] = []
        if !bytes.wifi.isZero { parts.append("Wi-Fi \(bytes.wifi.total.bytesText)") }
        if !bytes.cellular.isZero { parts.append("Cellular \(bytes.cellular.total.bytesText)") }
        return parts.joined(separator: " · ")
    }
}

struct AssignTarget: Identifiable {
    let domain: String
    var id: String { domain }
}

/// Picks the app a domain belongs to: a built-in app, one of the user's apps, or a new one.
struct AssignDomainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let domain: String
    @State private var search = ""
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New app name", text: $newName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(createNew)
                        Button("Create", action: createNew)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("New app")
                }

                let custom = model.customAppNames.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
                if !custom.isEmpty {
                    Section("Your apps") {
                        ForEach(custom, id: \.self) { name in
                            choiceRow(id: .custom(name))
                        }
                    }
                }

                Section("Built-in apps") {
                    ForEach(catalogMatches) { app in
                        choiceRow(id: .app(app.id))
                    }
                }

                if model.assignment(for: domain) != nil {
                    Section {
                        Button("Use Built-in Grouping", role: .destructive) {
                            model.assign(domain: domain, to: nil)
                            dismiss()
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search apps")
            .navigationTitle(domain)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var catalogMatches: [AppDefinition] {
        AppCatalog.all
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func choiceRow(id: EntryID) -> some View {
        let info = AppResolver.info(for: id)
        let selected = model.assignment(for: domain) == id
        return Button {
            model.assign(domain: domain, to: id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                EntryIcon(info: info, size: 28)
                Text(info.name).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }

    private func createNew() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.assign(domain: domain, to: .custom(name))
        dismiss()
    }
}
