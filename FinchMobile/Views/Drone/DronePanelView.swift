import SwiftUI

struct DronePanelView: View {
    @Environment(AppModel.self) private var app
    @State private var flash: String = ""
    @State private var searchText: String = ""
    @State private var sortMode: DroneSortMode = .threat
    @State private var onlyBLEDrones = false

    private enum DroneSortMode: String, CaseIterable, Identifiable {
        case threat
        case lastSeen
        case name
        case rssi

        var id: String { rawValue }
        var label: String {
            switch self {
            case .threat: return "Threat"
            case .lastSeen: return "Last seen"
            case .name: return "Name"
            case .rssi: return "RSSI"
            }
        }
    }

    private var bleDroneDevices: [BLEDevice] {
        var state = app.bleScanner.listFilter
        state.quickCategory = .drone
        state.searchText = searchText
        state.sortMode = .rssi
        return BLEListFilterEngine.filtered(Array(app.bleScanner.devices.values), state: state)
    }

    private var filteredTracks: [RFTrack] {
        var list = app.drone.detections
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.displayName.lowercased().contains(q)
                    || ($0.droneMeta?.vendorGuess?.lowercased().contains(q) ?? false)
                    || ($0.droneMeta?.linkType?.lowercased().contains(q) ?? false)
                    || $0.deviceClass.rawValue.lowercased().contains(q)
            }
        }
        switch sortMode {
        case .threat:
            list.sort { $0.threatScore > $1.threatScore }
        case .lastSeen:
            list.sort { $0.lastSeen > $1.lastSeen }
        case .name:
            list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .rssi:
            list.sort { ($0.rssi ?? -999) > ($1.rssi ?? -999) }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                List {
                    Section("Status") {
                        Text(app.drone.statusText)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                        Text(app.consent.statusSummary)
                            .font(FinchTheme.monoSmall)
                        if let last = app.drone.lastActiveResult {
                            Text(last)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                        Text("BLE drone-class ads: \(bleDroneDevices.count)")
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.warn)
                    }

                    Section("Filter / sort") {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            TextField("Search drones…", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .font(FinchTheme.monoSmall)
                        Picker("Sort", selection: $sortMode) {
                            ForEach(DroneSortMode.allCases) { m in
                                Text(m.label).tag(m)
                            }
                        }
                        Toggle("Show BLE drone ads", isOn: $onlyBLEDrones)
                            .font(FinchTheme.monoSmall)
                        Button("Open BLE Radar → Drones filter") {
                            app.bleScanner.listFilter.quickCategory = .drone
                        }
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                    }

                    if onlyBLEDrones {
                        Section("BLE drone / UAV advertisements (\(bleDroneDevices.count))") {
                            if bleDroneDevices.isEmpty {
                                Text("No BLE ads classified as Drone / UAV yet. Keep BLE Radar scanning.")
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(bleDroneDevices) { device in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.displayName)
                                        .font(FinchTheme.mono)
                                    Text("\(device.primaryCategory.label) · \(device.rssi) dBm · \(device.distanceShortLabel)")
                                        .font(FinchTheme.monoSmall)
                                        .foregroundStyle(.secondary)
                                    if let company = device.manufacturerCompanyId {
                                        Text(BLEValueExplainer.explainCompanyId(company))
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.cyan)
                                    }
                                    if let raw = device.manufacturerDataRawHex, !raw.isEmpty {
                                        Text("mfg hex: \(raw)")
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.warn)
                                            .finchCopyable(raw)
                                    }
                                }
                                .listRowBackground(FinchTheme.background)
                                .contextMenu {
                                    Button("Copy report") { FinchCopy.set(device.copyText) }
                                    Button("Copy JSON") { FinchCopy.set(device.exportJSONString) }
                                }
                            }
                        }
                    }

                    Section("Detections (passive)") {
                        if filteredTracks.isEmpty {
                            Text("No drone-class tracks yet. Scan BLE / Glass, or inject in Research Mode.")
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(filteredTracks) { track in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(track.displayName)
                                        .font(FinchTheme.mono)
                                    Spacer()
                                    Text("\(track.threatScore)/10")
                                        .font(FinchTheme.mono)
                                        .foregroundStyle(FinchTheme.cyan)
                                }
                                Text(track.droneMeta?.linkType ?? track.deviceClass.rawValue)
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(.secondary)
                                if let rssi = track.rssi {
                                    Text("RSSI \(rssi) dBm")
                                        .font(FinchTheme.monoSmall)
                                        .foregroundStyle(FinchTheme.warn)
                                }
                                HStack {
                                    Button("Observe") {
                                        app.drone.observeMAVLink(trackId: track.id)
                                        flash = app.drone.lastActiveResult ?? ""
                                    }
                                    .buttonStyle(.bordered)
                                    Menu("Active…") {
                                        ForEach(ActiveOpKind.allCases.filter { $0 != .armSystem }) { kind in
                                            Button(kind.title) {
                                                flash = app.drone.requestActive(kind: kind, track: track)
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(FinchTheme.cyan)
                                }
                            }
                            .listRowBackground(FinchTheme.background)
                        }
                    }

                    Section("Hard ceiling") {
                        Text("Passive detect / classify / forensic log: YES on stock iPhone.\nMITM · inject · fuzz · GPS spoof · RF deny · MAVLink Tx: require authorized external SDR/C2 kit. Finch arms, consents, and audits — it does not transmit RF.")
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(.secondary)
                    }

                    if !flash.isEmpty {
                        Section("Last result") {
                            Text(flash).font(FinchTheme.monoSmall)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("DRONE MODULE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        app.refreshFusion()
                        app.drone.refresh(from: app.fusion.sortedTracks)
                    }
                }
            }
            .onAppear {
                app.refreshFusion()
                app.drone.refresh(from: app.fusion.sortedTracks)
            }
        }
    }
}
