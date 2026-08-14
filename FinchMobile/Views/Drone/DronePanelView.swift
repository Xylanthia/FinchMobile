import SwiftUI

/// BLE advertisements classified as drone/UAV only. No RF Tx, no fake “active” ops.
struct DronePanelView: View {
    @Environment(AppModel.self) private var app
    @State private var searchText: String = ""

    private var bleDroneDevices: [BLEDevice] {
        var state = app.bleScanner.listFilter
        state.quickCategory = .drone
        state.searchText = searchText
        state.sortMode = .rssi
        return BLEListFilterEngine.filtered(Array(app.bleScanner.devices.values), state: state)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                List {
                    Section {
                        Text("Lists BLE ads whose name or company is DJI / Autel / Skydio / UAV. This phone cannot receive MAVLink RF or transmit.")
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(.secondary)
                        Text("\(bleDroneDevices.count) matching BLE ads")
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                    }
                    Section {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            TextField("Search…", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .font(FinchTheme.monoSmall)
                    }
                    Section("BLE drone / UAV") {
                        if bleDroneDevices.isEmpty {
                            Text("None yet. Leave Nearby scanning. Empty means nothing advertised those names — not a hidden RF detector.")
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(bleDroneDevices) { device in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.displayName).font(FinchTheme.mono)
                                Text("\(device.rssi.map { "\($0) dBm" } ?? "not_available") · \(device.distanceShortLabel)")
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(.secondary)
                                if !device.friendly.evidence.isEmpty {
                                    Text(device.friendly.evidence.joined(separator: " · "))
                                        .font(FinchTheme.monoSmall)
                                        .foregroundStyle(FinchTheme.cyan)
                                }
                            }
                            .listRowBackground(FinchTheme.background)
                            .contextMenu {
                                Button("Copy report") { FinchCopy.set(device.copyText) }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("DRONE (BLE only)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
