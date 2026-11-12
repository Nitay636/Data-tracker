import SwiftUI
import DataTrackerCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmInstall = false

    var body: some View {
        NavigationStack {
            Form {
                monthSection
                trackingSection
                autoResumeSection
                Section {
                    NavigationLink("Domain Assignments") { AssignmentsView() }
                } header: {
                    Text("Apps")
                } footer: {
                    Text("Domains you've moved to a different app or grouped under your own app name.")
                }
                Section {
                    LabeledContent("Stored on this iPhone", value: model.databaseSize.bytesText)
                    LabeledContent("History kept", value: "Forever")
                } header: {
                    Text("Data")
                } footer: {
                    Text("Nothing leaves your iPhone. The tracking VPN only counts bytes and the host names apps connect to; it doesn't read or store content.")
                }
                Section("How it's measured") {
                    Text("Wi-Fi and cellular totals come from the iPhone's network counters and are accurate whether or not tracking is on. Per-app numbers come from the on-device VPN, which groups traffic by the domains apps connect to, so they're close estimates.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .alert("Add the tracking VPN?", isPresented: $confirmInstall) {
                Button("Continue") { Task { await model.vpn.turnOn(); model.reload() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("iOS will ask to add a VPN configuration. It runs only on this iPhone: no server, no data leaves the device. It lets DataTracker see which domains each connection goes to so it can show usage per app.")
            }
        }
    }

    private var monthSection: some View {
        Section {
            Picker("Month means", selection: Binding(get: { model.monthMode }, set: { model.setMonthMode($0) })) {
                ForEach(MonthMode.allCases) { Text($0.title).tag($0) }
            }
            if model.monthMode == .billingCycle {
                Stepper(value: Binding(get: { model.billingDay }, set: { model.setBillingDay($0) }), in: 1...31) {
                    LabeledContent("Plan resets on day", value: "\(model.billingDay)")
                }
            }
        } header: {
            Text("Month view")
        } footer: {
            switch model.monthMode {
            case .billingCycle: Text("Matches your carrier bill. In shorter months, day \(model.billingDay) becomes the month's last day.")
            case .rolling30: Text("Always the last 30 days, including today.")
            case .calendarMonth: Text("From the 1st of the month.")
            }
        }
    }

    private var trackingSection: some View {
        let vpn = model.vpn
        return Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText)
                }
            }
            Toggle("Per-app tracking", isOn: Binding(
                get: { vpn.phase == .on || vpn.phase == .connecting },
                set: { on in
                    if on {
                        if vpn.isInstalled { Task { await vpn.turnOn(); model.reload() } } else { confirmInstall = true }
                    } else {
                        Task { await vpn.turnOff(); model.reload() }
                    }
                }))
                .disabled(vpn.isBusy)
            if let error = vpn.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Per-app tracking")
        } footer: {
            Text("Uses an on-device VPN. It stays on until you turn it off here, and reconnects by itself after restarts.")
        }
    }

    private var autoResumeSection: some View {
        Section {
            Toggle("Resume after another VPN", isOn: Binding(get: { model.autoResume }, set: { model.setAutoResume($0) }))
            if let date = AppGroup.settings.lastAutoResume {
                LabeledContent("Last resumed", value: date.formatted(.relative(presentation: .named)))
            }
        } header: {
            Text("Other VPNs")
        } footer: {
            Text("iOS runs one VPN at a time. When you switch to another VPN, tracking pauses. With this on, DataTracker turns tracking back on once that VPN is disconnected: right away when you open the app, otherwise the next time iOS gives it background time (usually within the hour). For an instant switch, add the “Start Tracking” shortcut to Control Center or the Action button.")
        }
    }

    private var statusText: String {
        switch model.vpn.phase {
        case .notInstalled: return "Not set up"
        case .off: return "Off"
        case .connecting: return "Connecting…"
        case .on: return "On"
        case .disconnecting: return "Turning off…"
        case .paused: return model.vpn.otherVPNActive ? "Paused (another VPN is on)" : "Paused"
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
                ContentUnavailableView("No assignments", systemImage: "arrow.triangle.merge",
                                       description: Text("Open an app or domain and long-press a domain to assign it."))
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
