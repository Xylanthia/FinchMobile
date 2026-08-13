import SwiftUI
import UIKit

struct BLERadarView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedID: UUID?
    @State private var copyBanner: String?

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
                        ForEach(app.bleScanner.sortedDevices) { device in
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
                    Button {
                        let all = app.bleScanner.sortedDevices.map(\.copyText)
                            .joined(separator: "\n\n————\n\n")
                        flashCopy(
                            all.isEmpty ? "No devices yet" : all,
                            note: all.isEmpty ? "Nothing to copy" : "All \(app.bleScanner.devices.count) devices copied"
                        )
                    } label: {
                        Image(systemName: "doc.on.doc.fill")
                    }
                    .accessibilityLabel("Copy all results")

                    Text("\(app.bleScanner.devices.count)")
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
            Text("Long-press any row to copy · clipboard button copies everything · distance is an RSSI estimate.")
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
        }
        .padding()
        .background(FinchTheme.surface)
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

struct BLEDeviceRow: View {
    let device: BLEDevice

    private var identity: BLEFriendlyIdentity { device.friendly }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: identity.icon)
                .font(.title3)
                .foregroundStyle(FinchTheme.cyan)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(identity.title)
                    .font(FinchTheme.mono)
                    .foregroundStyle(FinchTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(identity.deviceType)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                    Text("·")
                        .foregroundStyle(FinchTheme.textSecondary)
                    Text(identity.category)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.textSecondary)
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
    @State private var showTechnical = false
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
                                    Text(identity.category)
                                        .font(FinchTheme.monoSmall)
                                        .foregroundStyle(FinchTheme.textSecondary)
                                        .finchCopyable(identity.category)
                                }
                            }
                            .padding(.vertical, 4)

                            Text(identity.summary)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.textSecondary)
                                .finchCopyable(identity.summary)

                            copyRow("Device type", identity.deviceType)
                            copyRow("Confidence", identity.confidence)
                            copyRow("Distance", device.distanceLabel)
                            copyRow("Signal", "\(device.signalLabel) (\(device.rssi) dBm)")
                            copyRow("Status", device.connectionLabel)
                            copyRow("Connection", device.connectabilityLabel)
                            if let name = device.broadcastName {
                                copyRow("Resolved name", name)
                            }
                            if let brand = device.manufacturerName {
                                copyRow("Brand hint", brand)
                            }
                            if let company = device.manufacturerCompanyId {
                                copyRow("Company ID", String(format: "0x%04X", company))
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
                            Section("What's inside") {
                                ForEach(device.gattServices) { svc in
                                    let svcLabel = BLEServiceNames.label(forUUID: svc.uuid)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(svcLabel)
                                            .font(FinchTheme.mono)
                                            .foregroundStyle(FinchTheme.cyan)
                                            .finchCopyable(svcLabel)
                                        ForEach(svc.characteristics) { ch in
                                            let chLabel = BLEServiceNames.label(forUUID: ch.uuid)
                                            let valueText = ch.valueUTF8
                                                ?? (ch.valueHex.map { simpleValueHint(hex: $0, utf: nil) })
                                                ?? ""
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
                                                if !valueText.isEmpty {
                                                    Text(valueText)
                                                        .font(FinchTheme.monoSmall)
                                                        .foregroundStyle(FinchTheme.textPrimary)
                                                        .finchCopyable(valueText, label: "Copy value")
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
                                copyRow("ID", device.identifier.uuidString)
                                copyRow(
                                    "Company ID",
                                    device.manufacturerCompanyId.map { String(format: "0x%04X", $0) } ?? "—"
                                )
                                copyRow("Manufacturer data", device.manufacturerDataHex ?? "—")
                                if !device.serviceUUIDs.isEmpty {
                                    ForEach(device.serviceUUIDs, id: \.self) { uuid in
                                        Text(uuid)
                                            .font(FinchTheme.monoSmall)
                                            .finchCopyable(uuid)
                                    }
                                }
                                Text(device.advertisementHex)
                                    .font(FinchTheme.monoSmall)
                                    .finchCopyable(device.advertisementHex, label: "Copy advertisement")
                            }
                        } header: {
                            Text("Advanced")
                        } footer: {
                            Text("Double-tap or long-press any value to copy. Distance is estimated from signal strength.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(FinchTheme.background)
                    .navigationTitle(identity.category)
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

    private func simpleValueHint(hex: String, utf: String?) -> String {
        if let utf, !utf.isEmpty { return utf }
        let bytes = hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        if bytes.count == 1 {
            return "Value: \(bytes[0])"
        }
        if bytes.count == 2 {
            let v = Int(bytes[0]) | (Int(bytes[1]) << 8)
            return "Value: \(v)"
        }
        return "Raw data: \(hex)"
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
