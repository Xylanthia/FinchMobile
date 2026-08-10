import SwiftUI
import UIKit

struct BLERadarView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedID: UUID?

    private var selectedDevice: BLEDevice? {
        guard let selectedID else { return nil }
        return app.bleScanner.devices[selectedID]
    }

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
                                selectedID = device.identifier
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
            .sheet(isPresented: Binding(
                get: { selectedID != nil },
                set: { if !$0 { selectedID = nil } }
            )) {
                if let device = selectedDevice {
                    BLEDeviceDetailSheet(deviceID: device.identifier)
                        .environment(app)
                }
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
            Text("AllowDuplicates · GATT Connect/Read · TPMS / phones / wearables / beacons")
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
                if device.connectionState == .connected || device.connectionState == .discovering {
                    Text("GATT")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                }
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
    let deviceID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var device: BLEDevice? {
        app.bleScanner.devices[deviceID]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let device {
                    List {
                        Section("Device") {
                            row("UUID", device.identifier.uuidString)
                            row("Name", device.displayName)
                            row("RSSI", "\(device.rssi) dBm")
                            row("Connectable", device.connectable ? "yes" : "no")
                            row("State", device.connectionState.rawValue)
                            if let tx = device.txPower { row("Tx Power", "\(tx)") }
                            if let err = device.gattError {
                                Text(err)
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.danger)
                            }
                        }
                        Section("Manufacturer") {
                            row("Company", device.manufacturerName ?? device.manufacturerCompanyId.map { String(format: "0x%04X", $0) } ?? "—")
                            row("Data", device.manufacturerDataHex ?? "—")
                        }
                        Section("Advertised Services") {
                            if device.serviceUUIDs.isEmpty {
                                Text("None in advertisement")
                            } else {
                                ForEach(device.serviceUUIDs, id: \.self) { Text($0).font(FinchTheme.monoSmall) }
                            }
                        }
                        if !device.gattServices.isEmpty {
                            Section("GATT Map") {
                                ForEach(device.gattServices) { svc in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(svc.uuid)
                                            .font(FinchTheme.mono)
                                            .foregroundStyle(FinchTheme.cyan)
                                        ForEach(svc.characteristics) { ch in
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    Text(ch.uuid)
                                                        .font(FinchTheme.monoSmall)
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
                                                Text(ch.properties.joined(separator: " · "))
                                                    .font(FinchTheme.monoSmall)
                                                    .foregroundStyle(FinchTheme.textSecondary)
                                                if let hex = ch.valueHex, !hex.isEmpty {
                                                    Text(hex)
                                                        .font(FinchTheme.monoSmall)
                                                        .foregroundStyle(FinchTheme.textPrimary)
                                                        .textSelection(.enabled)
                                                }
                                                if let utf = ch.valueUTF8, !utf.isEmpty {
                                                    Text(utf)
                                                        .font(FinchTheme.monoSmall)
                                                        .foregroundStyle(FinchTheme.cyan.opacity(0.85))
                                                        .textSelection(.enabled)
                                                }
                                            }
                                            .padding(.leading, 4)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        Section("Raw Advertisement") {
                            Text(device.advertisementHex)
                                .font(FinchTheme.monoSmall)
                                .textSelection(.enabled)
                        }
                        Section {
                            if device.connectionState == .connected
                                || device.connectionState == .discovering
                                || device.connectionState == .connecting {
                                Button("Disconnect", role: .destructive) {
                                    app.bleScanner.disconnect()
                                }
                            } else {
                                Button(device.connectable ? "Connect + Map GATT" : "Try Connect (ad says non-connectable)") {
                                    app.bleScanner.connect(to: device.identifier)
                                }
                                .foregroundStyle(FinchTheme.cyan)
                            }
                            Button("Copy UUID") {
                                UIPasteboard.general.string = device.identifier.uuidString
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            ShareLink(item: exportText(device)) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(FinchTheme.background)
                    .navigationTitle(device.shortUUID)
                } else {
                    Text("Device gone")
                        .foregroundStyle(FinchTheme.textSecondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func exportText(_ device: BLEDevice) -> String {
        var lines = [
            "UUID: \(device.identifier.uuidString)",
            "Name: \(device.displayName)",
            "RSSI: \(device.rssi)",
            "State: \(device.connectionState.rawValue)",
            "Manufacturer: \(device.manufacturerName ?? "—") \(device.manufacturerDataHex ?? "")",
            "Services: \(device.serviceUUIDs.joined(separator: ", "))",
            "Advertisement: \(device.advertisementHex)"
        ]
        for svc in device.gattServices {
            lines.append("GATT Service \(svc.uuid)")
            for ch in svc.characteristics {
                lines.append("  Char \(ch.uuid) [\(ch.properties.joined(separator: ","))] hex=\(ch.valueHex ?? "") utf=\(ch.valueUTF8 ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            Spacer()
            Text(v).font(FinchTheme.mono).textSelection(.enabled)
        }
    }
}
