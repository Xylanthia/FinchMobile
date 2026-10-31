import SwiftUI

struct ARIABLEView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let devices = app.aria.history.ble
        List {
            Section {
                ARIAHistoryBanner()
                ARIASourceCounts(source: .ble)
            }
            if devices.isEmpty {
                ARIAEmptyRow(connected: app.aria.connection.state.isConnected)
            }
            ForEach(devices) { d in
                NavigationLink {
                    ARIABLEDetail(device: d)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(d.name?.isEmpty == false ? d.name! : "unknown")
                                .font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                            Spacer()
                            if let r = d.rssi { Text("\(r) dBm").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary) }
                        }
                        Text(d.address).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan)
                        ARIARangeTag(source: .ble, id: d.address)
                        HStack(spacing: 8) {
                            if let v = d.vendor { Text(v).font(.caption2.weight(.semibold)).foregroundStyle(FinchTheme.textPrimary) }
                            if let k = d.kind { Text(k).font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                            if d.randomized == true { Text("random addr").font(.caption2).foregroundStyle(FinchTheme.warn) }
                            if let c = d.companyID { Text("mfr \(c)").font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                            if let seen = d.seenCount { Text("×\(seen)").font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                        }
                        ARIAFingerprintView(decode: d.decode)
                    }
                }
                .listRowBackground(FinchTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle("BLE")
    }
}

struct ARIABLEDetail: View {
    let device: ARIABLEDeviceRecord

    private var fields: [(String, String?)] {
        var rows: [(String, String?)] = []
        rows.append(("name", device.name))
        rows.append(("address", device.address))
        rows.append(("vendor", device.vendor))
        rows.append(("company ID", device.companyID))
        rows.append(("kind", device.kind))
        rows.append(("band", device.band))
        rows.append(("channel", device.channel.map(String.init)))
        rows.append(("randomized address", device.randomized.map { $0 ? "yes" : "no" }))
        rows.append(("RSSI", device.rssi.map { "\($0) dBm" }))
        rows.append(("average RSSI", device.avgRSSI.map { String(format: "%.1f dBm", $0) }))
        rows.append(("packet rate", device.packetRate.map { String(format: "%.2f /s", $0) }))
        rows.append(("seen count", device.seenCount.map(String.init)))
        rows.append(("last seen", device.lastSeenAgoMs.map { "\($0 / 1000) s ago" }))
        rows.append(("first seen", device.firstSeenAgoMs.map { "\($0 / 1000) s ago" }))
        rows.append(("first seen (handheld uptime)", device.firstSeenUptimeMs.map { "\($0) ms" }))
        rows.append(("last seen (handheld uptime)", device.lastSeenUptimeMs.map { "\($0) ms" }))
        return rows
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ARIADeviceFieldsCard(rows: fields)
                ARIAFingerprintView(decode: device.decode)
                ARIAEvidenceSection(address: device.address)
                if let ad = device.adStructures, !ad.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AD structures").font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                        ForEach(ad.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            Text("\(k): \(v)").font(FinchTheme.monoSmall).finchCopyable(v)
                        }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading).background(FinchCardBackground())
                }
                ARIADecodeDetail(decode: device.decode)
                ARIAStoredRecordSection(source: .ble, key: device.address)
            }
            .padding()
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .navigationTitle(device.address)
        .navigationBarTitleDisplayMode(.inline)
    }
}
