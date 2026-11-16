import StoreKit
import SwiftUI
import DataTrackerCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.requestReview) private var requestReview
    @State private var confirmInstall = false
    @State private var pendingRetention: RetentionPeriod?
    @State private var keyboardUp = false

    var body: some View {
        NavigationStack {
            Form {
                trackingSection
                Section("Month view") {
                    Picker("Month means", selection: Binding(get: { model.monthMode }, set: { model.setMonthMode($0) })) {
                        ForEach(MonthMode.allCases) { Text($0.title).tag($0) }
                    }
                    if model.monthMode == .billingCycle {
                        Stepper(value: Binding(get: { model.billingDay }, set: { model.setBillingDay($0) }), in: 1...31) {
                            LabeledContent("Plan resets on day", value: "\(model.billingDay)")
                        }
                    }
                }
                Section("Data") {
                    Picker("Keep history", selection: Binding(get: { model.retention }, set: { newValue in
                        if let cutoff = newValue.cutoff(now: Date()), (model.retention.cutoff(now: Date()) ?? .distantPast) < cutoff {
                            pendingRetention = newValue // shorter than before: confirm deletion
                        } else {
                            model.setRetention(newValue)
                        }
                    })) {
                        ForEach(RetentionPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Storage used", value: model.databaseSize.bytesText)
                    NavigationLink("Domain Assignments") { AssignmentsView() }
                }
                Section {
                    Button {
                        model.showOnboarding = true
                    } label: {
                        Label("Introduction", systemImage: "sparkles")
                    }
                    Button {
                        requestReview()
                    } label: {
                        Label("Rate DataTracker", systemImage: "star")
                    }
                }
                ContactDeveloperSection(isFocused: $keyboardUp)
                Section {
                    LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                }
                Section {
                    VStack(spacing: 10) {
                        Text(AppInfo.name)
                            .font(.headline)
                        Image("AppIconImage")
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .keyboardFirstSwipe($keyboardUp)
            .navigationTitle("Settings")
            .alert("Add the tracking VPN?", isPresented: $confirmInstall) {
                Button("Continue") { Task { await model.vpn.turnOn(); model.reload() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It runs only on this iPhone.")
            }
            .confirmationDialog("Delete older history?", isPresented: Binding(get: { pendingRetention != nil },
                                                                               set: { if !$0 { pendingRetention = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let pendingRetention { model.setRetention(pendingRetention) }
                    pendingRetention = nil
                }
            } message: {
                if let pendingRetention {
                    Text("Usage older than \(pendingRetention.title) will be deleted.")
                }
            }
        }
    }

    private var trackingSection: some View {
        let vpn = model.vpn
        return Section("Per-app tracking") {
            Toggle(isOn: Binding(
                get: { vpn.phase == .on || vpn.phase == .connecting },
                set: { on in
                    if on {
                        if vpn.isInstalled { Task { await vpn.turnOn(); model.reload() } } else { confirmInstall = true }
                    } else {
                        Task { await vpn.turnOff(); model.reload() }
                    }
                })) {
                HStack(spacing: 8) {
                    Text("Tracking")
                    if vpn.isBusy || vpn.phase == .connecting || vpn.phase == .disconnecting {
                        ProgressView()
                    } else {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(statusText).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(vpn.isBusy)
            Toggle("Resume after other VPN", isOn: Binding(get: { model.autoResume }, set: { model.setAutoResume($0) }))
            if let error = vpn.lastError ?? AppGroup.settings.lastTunnelError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var statusText: String {
        switch model.vpn.phase {
        case .notInstalled, .off: return "Off"
        case .connecting: return "Connecting"
        case .on: return "On"
        case .disconnecting: return "Turning off"
        case .paused: return "Paused"
        }
    }

    private var statusColor: Color {
        switch model.vpn.phase {
        case .on: return .green
        case .connecting, .disconnecting: return .yellow
        case .paused: return .orange
        case .off, .notInstalled: return .gray
        }
    }
}

struct AssignmentsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("order.assignments") private var order = ListOrder(key: .date, ascending: false)

    var body: some View {
        let items = order.sorted(model.mappings.map { (domain: $0.key, target: $0.value) },
                                 amount: { model.report?.usage(ofDomain: $0.domain).bytes.total ?? 0 },
                                 date: { model.mappingDates[$0.domain] })
        List {
            if items.isEmpty {
                ContentUnavailableView("No assignments", systemImage: "arrow.triangle.merge")
            } else {
                ListOrderRow(order: $order)
            }
            ForEach(items, id: \.domain) { item in
                let info = EntryID(key: item.target).map(AppResolver.info(for:))
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.domain)
                        Text(info?.name ?? item.target).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let info { EntryIcon(info: info, size: 24) }
                }
            }
            .onDelete { offsets in
                for index in offsets { model.assign(domain: items[index].domain, to: nil) }
            }
        }
        .navigationTitle("Domain Assignments")
    }
}
