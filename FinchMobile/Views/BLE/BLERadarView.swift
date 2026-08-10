import SwiftUI
import UIKit

struct BLERadarView: View {
    @Environment(AppModel.self) private var app
    @State private var selected: BLEDevice?

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    controls
                    if let err = app.bleScanner.errorMessage {
                        Text(err)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.danger)
                            .padding(8)
                    }
                    List {
                        ForEach(app.bleScanner.sortedDevices) { device in
                            Button {
                                selected = device
                            } label: {
                                BLEDeviceRow(device: device)
                            }
                            .listRowBackground(FinchTheme.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("BLE RADAR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(app.bleScanner.devices.count)")
                        .font(FinchTheme.mono)
                        .foregroundStyle(FinchTheme.cyan)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { app.bleScanner.clearDevices() }
                }
            }
            .sheet(item: $selected) { device in
                BLEDeviceDetailSheet(device: device)
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
                Text("Continuous Scan")
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
            Text("AllowDuplicates · motion-aware live ads · TPMS / phones / wearables / beacons")
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
        }
        .padding()
        .background(FinchTheme.surface)
    }
}

struct BLEDeviceRow: View {
    let device: BLEDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(device.shortUUID)
                    .font(FinchTheme.mono)
                    .foregroundStyle(FinchTheme.cyan)
                Text(device.displayName)
                    .font(FinchTheme.mono)
                    .foregroundStyle(FinchTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                signalView
                Text("\(device.rssi) dBm")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
            }
            if let mfg = device.manufacturerName ?? device.manufacturerCompanyId.map({ String(format: "0x%04X", $0) }) {
                Text("MFG \(mfg)  \(device.manufacturerDataHex ?? "")")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
                    .lineLimit(1)
            }
            if !device.serviceUUIDs.isEmpty {
                Text(device.serviceUUIDs.joined(separator: " "))
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.cyan.opacity(0.7))
                    .lineLimit(1)
            }
            Text(relative(device.lastSeen))
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private var signalView: some View {
        Image(systemName: signalIcon)
            .foregroundStyle(FinchTheme.cyan)
            .font(.caption)
    }

    private var signalIcon: String {
        switch device.signalBars {
        case 4: return "wifi"
        case 3: return "wifi"
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
    let device: BLEDevice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    row("UUID", device.identifier.uuidString)
                    row("Name", device.displayName)
                    row("RSSI", "\(device.rssi) dBm")
                    row("Connectable", device.connectable ? "yes" : "no")
                    if let tx = device.txPower { row("Tx Power", "\(tx)") }
                }
                Section("Manufacturer") {
                    row("Company", device.manufacturerName ?? device.manufacturerCompanyId.map { String(format: "0x%04X", $0) } ?? "—")
                    row("Data", device.manufacturerDataHex ?? "—")
                }
                Section("Services") {
                    if device.serviceUUIDs.isEmpty {
                        Text("None in advertisement")
                    } else {
                        ForEach(device.serviceUUIDs, id: \.self) { Text($0).font(FinchTheme.monoSmall) }
                    }
                }
                Section("Raw Advertisement") {
                    Text(device.advertisementHex)
                        .font(FinchTheme.monoSmall)
                        .textSelection(.enabled)
                }
                Section {
                    Button("Copy UUID") {
                        UIPasteboard.general.string = device.identifier.uuidString
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    ShareLink(item: exportText) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinchTheme.background)
            .navigationTitle(device.shortUUID)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var exportText: String {
        """
        UUID: \(device.identifier.uuidString)
        Name: \(device.displayName)
        RSSI: \(device.rssi)
        Manufacturer: \(device.manufacturerName ?? "—") \(device.manufacturerDataHex ?? "")
        Services: \(device.serviceUUIDs.joined(separator: ", "))
        Advertisement: \(device.advertisementHex)
        """
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            Spacer()
            Text(v).font(FinchTheme.mono).textSelection(.enabled)
        }
    }
}
