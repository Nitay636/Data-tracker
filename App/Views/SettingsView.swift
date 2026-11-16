import SwiftUI
import DataTrackerCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmInstall = false
    @State private var pendingRetention: RetentionPeriod?

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
            }
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
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText).foregroundStyle(.secondary)
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

    var body: some View {
        let items = model.mappings.sorted { $0.key < $1.key }
        List {
            if items.isEmpty {
                ContentUnavailableView("No assignments", systemImage: "arrow.triangle.merge")
            }
            ForEach(items, id: \.key) { item in
                let info = EntryID(key: item.value).map(AppResolver.info(for:))
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.key)
                        Text(info?.name ?? item.value).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let info { EntryIcon(info: info, size: 24) }
                }
            }
            .onDelete { offsets in
                for index in offsets { model.assign(domain: items[index].key, to: nil) }
            }
        }
        .navigationTitle("Domain Assignments")
    }
}
