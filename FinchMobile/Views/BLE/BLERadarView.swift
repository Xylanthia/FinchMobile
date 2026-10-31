import SwiftUI
import UIKit

struct BLERadarView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedID: UUID?
    @State private var copyBanner: String?
    @State private var showAdvancedFilter = false
    @State private var summaryExpanded = true

    private var selectedDevice: BLEDevice? {
        guard let selectedID else { return nil }
        return app.bleScanner.devices[selectedID]
    }

    private var filter: Binding<BLEListFilterState> {
        Binding(
            get: { app.bleScanner.listFilter },
            set: { app.bleScanner.listFilter = $0 }
        )
    }

    private var devices: [BLEDevice] { app.bleScanner.filteredDevices }
    private var summary: BLEScanSummary { app.bleScanner.scanSummary }

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    controls
                    summaryCard
                    filterBar
                    if let err = app.bleScanner.errorMessage {
                        Text(err)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.danger)
                            .padding(8)
                            .finchCopyable(err, label: "Copy error")
                    }
                    if let copyBanner {
                        Text(copyBanner)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                            .padding(6)
                            .transition(.opacity)
                    }
                    List {
                        ForEach(devices) { device in
                            Button {
                                selectedID = device.identifier
                            } label: {
                                BLEDeviceRow(device: device)
                            }
                            .listRowBackground(FinchTheme.surface)
                            .contextMenu {
                                Button {
                                    flashCopy(device.copyText, note: "Device copied")
                                } label: {
                                    Label("Copy this device", systemImage: "doc.on.doc")
                                }
                                Button {
                                    flashCopy(device.exportJSONString, note: "JSON copied")
                                } label: {
                                    Label("Copy JSON", systemImage: "curlybraces")
                                }
                                Button {
                                    flashCopy(device.copyCVEsText, note: "CVEs copied")
                                } label: {
                                    Label("Copy CVEs", systemImage: "ladybug")
                                }
                                Button {
                                    flashCopy(
                                        "\(device.friendly.title)\n\(device.distanceLabel)\n\(device.signalLabel)",
                                        note: "Distance copied"
                                    )
                                } label: {
                                    Label("Copy distance", systemImage: "ruler")
                                }
                                Button {
                                    flashCopy(device.identifier.uuidString, note: "ID copied")
                                } label: {
                                    Label("Copy ID", systemImage: "number")
                                }
                                Menu("Set category") {
                                    Button("Auto (clear override)") {
                                        app.bleScanner.setManualCategory(for: device.identifier, category: nil)
                                    }
                                    ForEach(BLEDeviceCategory.allCases) { cat in
                                        Button(cat.label) {
                                            app.bleScanner.setManualCategory(for: device.identifier, category: cat)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Nearby Bluetooth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { app.bleScanner.clearDevices() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        ForEach(BLESortMode.allCases) { mode in
                            Button {
                                app.bleScanner.listFilter.sortMode = mode
                            } label: {
                                HStack {
                                    Text(mode.label)
                                    if app.bleScanner.listFilter.sortMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")

                    Menu {
                        Button {
                            let all = devices.map(\.copyText).joined(separator: "\n\n————\n\n")
                            flashCopy(
                                all.isEmpty ? "No devices yet" : all,
                                note: all.isEmpty ? "Nothing to copy" : "\(devices.count) devices copied"
                            )
                        } label: {
                            Label("Copy visible text", systemImage: "doc.on.doc")
                        }
                        Button {
                            flashCopy(app.bleScanner.exportAllJSON(), note: "JSON export copied")
                        } label: {
                            Label("Copy JSON export", systemImage: "curlybraces")
                        }
                        ShareLink(item: app.bleScanner.exportAllJSON()) {
                            Label("Share JSON", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "doc.on.doc.fill")
                    }
                    .accessibilityLabel("Export")

                    Text("\(devices.count) shown / \(app.bleScanner.devices.count) phone BLE")
                        .font(FinchTheme.mono)
                        .foregroundStyle(FinchTheme.cyan)
                }
            }
            .sheet(isPresented: Binding(
                get: { selectedID != nil },
                set: { if !$0 { selectedID = nil } }
            )) {
                if let device = selectedDevice {
                    BLEDeviceDetailSheet(deviceID: device.identifier)
                        .environment(app)
                }
            }
            .sheet(isPresented: $showAdvancedFilter) {
                BLEAdvancedFilterSheet(filter: filter)
            }
            .onAppear {
                if app.settings.continuousBLEDefault {
                    app.bleScanner.continuousMode = true
                    app.bleScanner.start()
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { app.bleScanner.continuousMode },
                set: { app.bleScanner.toggleContinuous($0) }
            )) {
                Text("Keep scanning")
                    .font(FinchTheme.mono)
            }
            .tint(FinchTheme.cyan)

            HStack {
                Circle()
                    .fill(app.bleScanner.isScanning ? FinchTheme.cyan : FinchTheme.textSecondary)
                    .frame(width: 8, height: 8)
                Text(app.bleScanner.statusText)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
                    .finchCopyable(app.bleScanner.statusText)
                Spacer()
                Button(app.bleScanner.isScanning ? "Stop" : "Start") {
                    if app.bleScanner.isScanning {
                        app.bleScanner.stop()
                    } else {
                        app.bleScanner.start()
                    }
                }
                .buttonStyle(FinchOutlineButtonStyle())
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 4)
        .background(FinchTheme.surface)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { summaryExpanded.toggle() }
            } label: {
                HStack {
                    Text("Scan summary")
                        .font(FinchTheme.mono)
                        .foregroundStyle(FinchTheme.textPrimary)
                    Spacer()
                    Text("\(summary.total) devices")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                    Image(systemName: summaryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(FinchTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if summaryExpanded {
                HStack(spacing: 12) {
                    summaryStat("Visible", "\(devices.count)")
                    summaryStat("Connectable", "\(summary.connectable)")
                    if let rssi = summary.strongestRSSI {
                        summaryStat("Best RSSI", "\(rssi)")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(BLEDeviceCategory.quickFilterCases) { cat in
                            let n = summary.count(for: cat)
                            if n > 0 || cat == .unknown {
                                Text("\(cat.shortLabel) \(n)")
                                    .font(FinchTheme.monoSmall)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(FinchTheme.background)
                                    .foregroundStyle(n > 0 ? FinchTheme.cyan : FinchTheme.textSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .onTapGesture {
                                        app.bleScanner.listFilter.quickCategory = cat
                                    }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(FinchTheme.surface)
    }

    private func summaryStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
            Text(value)
                .font(FinchTheme.mono)
                .foregroundStyle(FinchTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FinchTheme.textSecondary)
                TextField(
                    "Search name, ID, UUID, company…",
                    text: Binding(
                        get: { app.bleScanner.listFilter.searchText },
                        set: { app.bleScanner.listFilter.searchText = $0 }
                    )
                )
                .font(FinchTheme.monoSmall)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                if !app.bleScanner.listFilter.searchText.isEmpty {
                    Button {
                        app.bleScanner.listFilter.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FinchTheme.textSecondary)
                    }
                }
            }
            .padding(8)
            .background(FinchTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    quickPill("All", selected: app.bleScanner.listFilter.quickCategory == nil) {
                        app.bleScanner.listFilter.quickCategory = nil
                    }
                    ForEach(BLEDeviceCategory.quickFilterCases) { cat in
                        quickPill(cat.shortLabel, selected: app.bleScanner.listFilter.quickCategory == cat) {
                            app.bleScanner.listFilter.quickCategory = cat
                        }
                    }
                }
            }

            HStack {
                Button {
                    showAdvancedFilter = true
                } label: {
                    Label(
                        app.bleScanner.listFilter.hasAdvancedActive ? "Advanced ●" : "Advanced",
                        systemImage: "slider.horizontal.3"
                    )
                    .font(FinchTheme.monoSmall)
                }
                .foregroundStyle(FinchTheme.cyan)

                Spacer()

                Text(app.bleScanner.listFilter.sortMode.label)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)

                if app.bleScanner.listFilter.activeFilterCount > 0 {
                    Button("Reset") {
                        app.bleScanner.listFilter.resetAll()
                    }
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.warn)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(FinchTheme.surface)
    }

    private func quickPill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FinchTheme.monoSmall)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? FinchTheme.cyan.opacity(0.25) : FinchTheme.background)
                .foregroundStyle(selected ? FinchTheme.cyan : FinchTheme.textSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? FinchTheme.cyan : FinchTheme.cyanDim, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func flashCopy(_ text: String, note: String) {
        FinchCopy.set(text)
        withAnimation { copyBanner = note }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                withAnimation { copyBanner = nil }
            }
        }
    }
}

struct BLEAdvancedFilterSheet: View {
    @Binding var filter: BLEListFilterState
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            Form {
                Section("Include categories") {
                    ForEach(BLEDeviceCategory.allCases) { cat in
                        Toggle(cat.label, isOn: Binding(
                            get: { filter.includeCategories.contains(cat) },
                            set: { on in
                                if on { filter.includeCategories.insert(cat) }
                                else { filter.includeCategories.remove(cat) }
                            }
                        ))
                    }
                }
                Section("Exclude categories") {
                    ForEach(BLEDeviceCategory.allCases) { cat in
                        Toggle(cat.label, isOn: Binding(
                            get: { filter.excludeCategories.contains(cat) },
                            set: { on in
                                if on { filter.excludeCategories.insert(cat) }
                                else { filter.excludeCategories.remove(cat) }
                            }
                        ))
                    }
                }
                Section("RSSI (dBm)") {
                    HStack {
                        Text("\(Int(filter.rssiMin))")
                        Slider(value: $filter.rssiMin, in: -100...(-20), step: 1)
                        Text("\(Int(filter.rssiMax))")
                    }
                    .font(FinchTheme.monoSmall)
                    Slider(value: $filter.rssiMax, in: -100...(-20), step: 1)
                }
                Section("Distance (m)") {
                    HStack {
                        Text(String(format: "%.0f", filter.distanceMin))
                        Slider(value: $filter.distanceMin, in: 0...100, step: 1)
                        Text(String(format: "%.0f", filter.distanceMax))
                    }
                    .font(FinchTheme.monoSmall)
                    Slider(value: $filter.distanceMax, in: 0...100, step: 1)
                }
                Section("Company ID") {
                    TextField("e.g. 0x0075", text: $filter.companyIdText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Name contains") {
                    TextField("substring", text: $filter.nameContains)
                }
                Section("Connectable") {
                    Picker("Connectable", selection: $filter.connectable) {
                        ForEach(BLEConnectableFilter.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Service UUID") {
                    TextField("e.g. 180D or FE2C", text: $filter.serviceUUID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if !app.bleScanner.knownAdvertisedServiceUUIDs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(app.bleScanner.knownAdvertisedServiceUUIDs.prefix(40), id: \.self) { uuid in
                                    Button(uuid) { filter.serviceUUID = uuid }
                                        .font(FinchTheme.monoSmall)
                                }
                            }
                        }
                    }
                }
                Section("Last seen") {
                    Picker("Window", selection: $filter.lastSeen) {
                        ForEach(BLELastSeenWindow.allCases) { w in
                            Text(w.label).tag(w)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinchTheme.background)
            .navigationTitle("Advanced filter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter.resetAdvanced() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct BLEDeviceRow: View {
    let device: BLEDevice

    private var identity: BLEFriendlyIdentity { device.friendly }
    private var flockHit: FlockCameraDetector.Hit? { FlockCameraDetector.matchBLE(device) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: identity.icon)
                .font(.title3)
                .foregroundStyle(flockHit != nil ? FinchTheme.warn : FinchTheme.cyan)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(identity.title)
                    .font(FinchTheme.mono)
                    .foregroundStyle(FinchTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let flock = flockHit {
                        Text(flock.badge)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.warn)
                    } else {
                        Text(identity.deviceType)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                    }
                    Text("·")
                        .foregroundStyle(FinchTheme.textSecondary)
                    Text(device.primaryCategory.shortLabel)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(device.manualCategoryOverride != nil ? FinchTheme.warn : FinchTheme.textSecondary)
                    Text("·")
                        .foregroundStyle(FinchTheme.textSecondary)
                    Text(identity.confidence)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.warn)
                }
                .lineLimit(1)

                Text(identity.summary)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
                    .lineLimit(2)

                Text(device.distanceLabel)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.warn)
                    .lineLimit(1)

                if !device.cves.isEmpty {
                    Text(device.cves.prefix(3).map(\.cve).joined(separator: "  "))
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.danger)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(device.distanceShortLabel)
                        .foregroundStyle(FinchTheme.warn)
                    Text("·")
                    Text(device.signalLabel)
                    Text("·")
                    Text(relative(device.lastSeen))
                    if !device.cves.isEmpty {
                        Text("·")
                        Text("CVE \(device.cves.count)")
                            .foregroundStyle(FinchTheme.danger)
                    }
                    if device.connectionState == .connected || device.connectionState == .discovering {
                        Text("·")
                        Text("Open")
                            .foregroundStyle(FinchTheme.cyan)
                    }
                }
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: signalIcon)
                .foregroundStyle(FinchTheme.cyan)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var signalIcon: String {
        switch device.signalBars {
        case 4, 3: return "wifi"
        case 2: return "wifi.exclamationmark"
        case 1: return "wifi.slash"
        default: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private func relative(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        return "\(s / 60)m ago"
    }
}

struct BLEDeviceDetailSheet: View {
    let deviceID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showTechnical = true
    @State private var copyBanner: String?

    private var device: BLEDevice? {
        app.bleScanner.devices[deviceID]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let device {
                    let identity = device.friendly
                    List {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: identity.icon)
                                    .font(.largeTitle)
                                    .foregroundStyle(FinchTheme.cyan)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(identity.title)
                                        .font(FinchTheme.mono)
                                        .foregroundStyle(FinchTheme.textPrimary)
                                        .finchCopyable(identity.title)
                                    Text(identity.deviceType)
                                        .font(FinchTheme.monoSmall)
                                        .foregroundStyle(FinchTheme.cyan)
                                        .finchCopyable(identity.deviceType)
                                    Text(device.resolvedCategories.map(\.label).joined(separator: ", "))
                                        .font(FinchTheme.monoSmall)
                                        .foregroundStyle(FinchTheme.textSecondary)
                                        .finchCopyable(device.resolvedCategories.map(\.label).joined(separator: ", "))
                                }
                            }
                            .padding(.vertical, 4)

                            Text(identity.summary)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.textSecondary)
                                .finchCopyable(identity.summary)

                            copyRow("Device type", identity.deviceType)
                            copyRow("Confidence", identity.confidence)
                            copyRow("Taxonomy", device.resolvedCategories.map(\.label).joined(separator: ", "))
                            if device.manualCategoryOverride != nil {
                                Text("Manual override active")
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.warn)
                            }
                            Menu("Reclassify…") {
                                Button("Auto (clear override)") {
                                    app.bleScanner.setManualCategory(for: device.identifier, category: nil)
                                }
                                ForEach(BLEDeviceCategory.allCases) { cat in
                                    Button(cat.label) {
                                        app.bleScanner.setManualCategory(for: device.identifier, category: cat)
                                    }
                                }
                            }
                            if let flock = FlockCameraDetector.matchBLE(device) {
                                copyRow("ALPR / Flock-class", "\(flock.vendor) · \(flock.model)")
                                Text(flock.reason)
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.warn)
                                    .finchCopyable(flock.reason)
                            }
                            copyRow("Distance", device.distanceLabel)
                            copyRow("Signal", "\(device.signalLabel) (\(device.rssi.map { "\($0) dBm" } ?? "not_available"))")
                            copyRow("Status", device.connectionLabel)
                            copyRow("Connection", device.connectabilityLabel)
                            if let name = device.broadcastName {
                                copyRow("Resolved name", name)
                            }
                            if let brand = device.manufacturerName {
                                copyRow("Brand hint", brand)
                            }
                            if let company = device.manufacturerCompanyId {
                                copyRow("Brand / company", BLEValueExplainer.explainCompanyId(company))
                            }
                            // Advertisement: summary + hex for manufacturer / service / tx / flags
                            if let mfg = device.manufacturerDataHex, !mfg.isEmpty {
                                copyRow(
                                    "Manufacturer summary",
                                    BLEValueExplainer.explainManufacturer(
                                        companyId: device.manufacturerCompanyId,
                                        brand: device.manufacturerName,
                                        payloadHex: mfg
                                    )
                                )
                            }
                            if let raw = device.manufacturerDataRawHex, !raw.isEmpty {
                                copyRow("Manufacturer hex (raw)", raw)
                            }
                            if let payload = device.manufacturerDataHex, !payload.isEmpty {
                                copyRow("Manufacturer hex (payload)", payload)
                            }
                            if let tx = device.txPower {
                                copyRow("Tx Power summary", "\(tx) dBm")
                                if let hx = device.txPowerHex {
                                    copyRow("Tx Power hex", hx)
                                }
                            }
                            if let flagsSummary = device.advertisementFlagsSummary {
                                copyRow("Flags summary", flagsSummary)
                            }
                            if let flagsHex = device.advertisementFlagsHex {
                                copyRow("Flags hex", flagsHex)
                            }
                            if !device.serviceData.isEmpty {
                                ForEach(device.serviceData.keys.sorted(), id: \.self) { uuid in
                                    let hex = device.serviceData[uuid] ?? ""
                                    copyRow(
                                        "Service data summary",
                                        BLEValueExplainer.explainServiceData(uuid: uuid, hex: hex)
                                    )
                                    copyRow("Service data hex (\(BLEServiceNames.shortKey(uuid)))", hex)
                                }
                            }
                            if !identity.serviceLabels.isEmpty {
                                copyRow("Advertises", identity.serviceLabels.joined(separator: ", "))
                            }
                            if let err = device.gattError {
                                Text(err)
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.danger)
                                    .finchCopyable(err)
                            }
                        } header: {
                            Text("What is this?")
                        }

                        if !device.cves.isEmpty {
                            Section("CVEs for this BLE finding (\(device.cves.count))") {
                                ForEach(device.cves) { cve in
                                    let block = "\(cve.cve) — \(cve.title)\n\(cve.why)\n\(cve.nvdURL)"
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(cve.cve)
                                                .font(FinchTheme.mono)
                                                .foregroundStyle(FinchTheme.danger)
                                            Text(cve.confidence)
                                                .font(FinchTheme.monoSmall)
                                                .foregroundStyle(FinchTheme.textSecondary)
                                        }
                                        Text(cve.title)
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.textPrimary)
                                        Text(cve.why)
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.textSecondary)
                                        Text(cve.nvdURL)
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.cyan.opacity(0.85))
                                    }
                                    .padding(.vertical, 2)
                                    .finchCopyable(block, label: "Copy CVE")
                                    .contextMenu {
                                        Button { flash("CVE copied"); FinchCopy.set(block) } label: {
                                            Label("Copy CVE", systemImage: "doc.on.doc")
                                        }
                                        Button { flash("CVE ID copied"); FinchCopy.set(cve.cve) } label: {
                                            Label("Copy ID only", systemImage: "number")
                                        }
                                        Button { flash("NVD link copied"); FinchCopy.set(cve.nvdURL) } label: {
                                            Label("Copy NVD link", systemImage: "link")
                                        }
                                    }
                                }
                                Button("Copy all CVEs") {
                                    flash("All CVEs copied")
                                    FinchCopy.set(device.copyCVEsText)
                                }
                            }
                        }

                        if !device.gattServices.isEmpty {
                            Section("GATT · \(BLEServiceNames.recognizedCount) UUID names loaded") {
                                ForEach(device.gattServices) { svc in
                                    let svcLabel = BLEServiceNames.label(forUUID: svc.uuid)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(svcLabel)
                                            .font(FinchTheme.mono)
                                            .foregroundStyle(FinchTheme.cyan)
                                            .finchCopyable(svcLabel)
                                        Text("UUID: \(svc.uuid)")
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.textSecondary)
                                            .finchCopyable(svc.uuid)
                                        ForEach(svc.characteristics) { ch in
                                            let chLabel = BLEServiceNames.label(forUUID: ch.uuid)
                                            let valueText = ch.valueSummary
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    Text(chLabel)
                                                        .font(FinchTheme.monoSmall)
                                                        .finchCopyable(chLabel)
                                                    Spacer()
                                                    if ch.properties.contains("read") {
                                                        Button("Read") {
                                                            app.bleScanner.readCharacteristic(
                                                                serviceUUID: svc.uuid,
                                                                characteristicUUID: ch.uuid
                                                            )
                                                        }
                                                        .font(FinchTheme.monoSmall)
                                                        .foregroundStyle(FinchTheme.cyan)
                                                    }
                                                }
                                                Text(BLEPropertyLabels.friendly(ch.properties))
                                                    .font(FinchTheme.monoSmall)
                                                    .foregroundStyle(FinchTheme.textSecondary)
                                                Text(valueText)
                                                    .font(FinchTheme.monoSmall)
                                                    .foregroundStyle(FinchTheme.textPrimary)
                                                    .finchCopyable(valueText, label: "Copy value summary")
                                                if let hex = ch.valueHex, !hex.isEmpty {
                                                    Text("hex: \(hex)")
                                                        .font(FinchTheme.monoSmall)
                                                        .foregroundStyle(FinchTheme.warn)
                                                        .finchCopyable(hex, label: "Copy hex")
                                                }
                                                ForEach(ch.descriptors) { desc in
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text("desc \(BLEServiceNames.label(forUUID: desc.uuid))")
                                                            .font(FinchTheme.monoSmall)
                                                            .foregroundStyle(FinchTheme.textSecondary)
                                                        Text(desc.valueSummary)
                                                            .font(FinchTheme.monoSmall)
                                                            .finchCopyable(desc.valueSummary)
                                                        if let hx = desc.valueHex, !hx.isEmpty {
                                                            Text("hex: \(hx)")
                                                                .font(FinchTheme.monoSmall)
                                                                .foregroundStyle(FinchTheme.warn)
                                                                .finchCopyable(hx)
                                                        }
                                                    }
                                                    .padding(.leading, 8)
                                                }
                                            }
                                            .padding(.leading, 4)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }

                        Section {
                            Button("Copy everything") {
                                flash("Full device report copied")
                                FinchCopy.set(device.copyText)
                            }
                            .foregroundStyle(FinchTheme.cyan)

                            Button("Copy JSON") {
                                flash("JSON copied")
                                FinchCopy.set(device.exportJSONString)
                            }
                            .foregroundStyle(FinchTheme.cyan)

                            ShareLink(item: device.exportJSONString) {
                                Label("Share JSON", systemImage: "square.and.arrow.up")
                            }

                            if device.connectionState == .connected
                                || device.connectionState == .discovering
                                || device.connectionState == .connecting {
                                Button("Disconnect", role: .destructive) {
                                    app.bleScanner.disconnect()
                                }
                            } else {
                                Button(device.connectable
                                       ? "Open device for more detail"
                                       : "Try open (may not work)") {
                                    app.bleScanner.connect(to: device.identifier)
                                }
                                .foregroundStyle(FinchTheme.cyan)
                            }
                            ShareLink(item: device.copyText) {
                                Label("Share summary", systemImage: "square.and.arrow.up")
                            }
                        }

                        Section {
                            Toggle("Show technical details", isOn: $showTechnical)
                                .font(FinchTheme.monoSmall)
                            if showTechnical {
                                copyRow("Phone-local ID", device.identifier.uuidString)
                                if let company = device.manufacturerCompanyId {
                                    copyRow("Brand / company", BLEValueExplainer.explainCompanyId(company))
                                }
                                if let raw = device.manufacturerDataRawHex {
                                    copyRow("Manufacturer hex (raw)", raw)
                                }
                                if !device.serviceUUIDs.isEmpty {
                                    ForEach(device.serviceUUIDs, id: \.self) { uuid in
                                        Text(BLEServiceNames.label(forUUID: uuid))
                                            .font(FinchTheme.monoSmall)
                                            .finchCopyable(BLEServiceNames.label(forUUID: uuid))
                                        Text(uuid)
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.textSecondary)
                                            .finchCopyable(uuid)
                                    }
                                }
                                Text(BLEValueExplainer.explainAdvertisementBlob(device.advertisementHex))
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.textSecondary)
                                    .finchCopyable(
                                        BLEValueExplainer.explainAdvertisementBlob(device.advertisementHex),
                                        label: "Copy advertisement summary"
                                    )
                                if !device.advertisementHex.isEmpty {
                                    Text(device.advertisementHex)
                                        .font(FinchTheme.monoSmall)
                                        .foregroundStyle(FinchTheme.warn)
                                        .finchCopyable(device.advertisementHex, label: "Copy advertisement dump")
                                }
                            }
                        } header: {
                            Text("Advanced")
                        } footer: {
                            Text("Double-tap or long-press any value to copy. Distance is estimated from signal strength. Raw hex shown alongside summaries.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(FinchTheme.background)
                    .navigationTitle(device.primaryCategory.shortLabel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                flash("Copied")
                                FinchCopy.set(device.copyText)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let copyBanner {
                            Text(copyBanner)
                                .font(FinchTheme.monoSmall)
                                .padding(10)
                                .background(FinchTheme.surface)
                                .foregroundStyle(FinchTheme.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding()
                        }
                    }
                } else {
                    Text("Device gone")
                        .foregroundStyle(FinchTheme.textSecondary)
                }
            }
        }
    }

    private func flash(_ note: String) {
        withAnimation { copyBanner = note }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run { withAnimation { copyBanner = nil } }
        }
    }

    private func copyRow(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            Text(v).font(FinchTheme.mono).finchCopyable(v, label: "Copy \(k)")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button { FinchCopy.set(v) } label: {
                Label("Copy \(k)", systemImage: "doc.on.doc")
            }
            Button { FinchCopy.set("\(k): \(v)") } label: {
                Label("Copy as \(k): value", systemImage: "text.append")
            }
        }
    }
}
