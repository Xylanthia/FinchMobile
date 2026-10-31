import SwiftUI

struct ARIAWiFiView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let devices = app.aria.history.wifi
        List {
            Section {
                ARIAHistoryBanner()
                ARIASourceCounts(source: .wifi)
            }
            if devices.isEmpty {
                ARIAEmptyRow(connected: app.aria.connection.state.isConnected)
            }
            ForEach(devices) { d in
                NavigationLink {
                    ARIAWiFiDetail(device: d)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(d.ssid?.isEmpty == false ? d.ssid! : "(hidden)")
                                .font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                            Spacer()
                            if let r = d.rssi { Text("\(r) dBm").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary) }
                        }
                        Text(d.mac).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan)
                        if let cam = d.bodyCam { ARIABodyCamBadge(match: cam) }
                        ARIARangeTag(source: .wifi, id: d.mac)
                        HStack(spacing: 8) {
                            if let k = d.kind { Text(k).font(.caption2.weight(.semibold)).foregroundStyle(FinchTheme.textPrimary) }
                            if let ch = d.channel { Text("ch \(ch)").font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                            if d.randomized == true { Text("random MAC").font(.caption2).foregroundStyle(FinchTheme.warn) }
                            if let r = d.packetRate { Text(String(format: "%.1f pkt/s", r)).font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                        }
                        HStack(spacing: 8) {
                            if let v = d.vendor { Text(v).font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                            if let enc = d.encryption { Text(enc).font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                            if let seen = d.seenCount { Text("×\(seen)").font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                            if d.hasEAPOL == true {
                                Text("EAPOL").font(.caption2.weight(.bold)).foregroundStyle(FinchTheme.warn)
                            }
                        }
                        ARIAFingerprintView(decode: d.decode)
                    }
                }
                .listRowBackground(FinchTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle("Wi-Fi")
    }
}

struct ARIAWiFiDetail: View {
    let device: ARIAWiFiDevice

    private var fields: [(String, String?)] {
        var rows: [(String, String?)] = []
        rows.append(("SSID", device.ssid))
        rows.append(("MAC", device.mac))
        rows.append(("BSSID", device.bssid))
        rows.append(("vendor", device.vendor))
        rows.append(("police body cam", device.bodyCam.map { "\($0.maker) (\($0.evidence))" }))
        rows.append(("kind", device.kind))
        rows.append(("band", device.band))
        rows.append(("channel", device.channel.map(String.init)))
        rows.append(("encryption", device.encryption))
        rows.append(("randomized MAC", device.randomized.map { $0 ? "yes" : "no" }))
        rows.append(("RSSI", device.rssi.map { "\($0) dBm" }))
        rows.append(("average RSSI", device.avgRSSI.map { String(format: "%.1f dBm", $0) }))
        rows.append(("packet rate", device.packetRate.map { String(format: "%.2f /s", $0) }))
        rows.append(("seen count", device.seenCount.map(String.init)))
        rows.append(("last seen", device.lastSeenAgoMs.map { "\($0 / 1000) s ago" }))
        rows.append(("first seen", device.firstSeenAgoMs.map { "\($0 / 1000) s ago" }))
        rows.append(("first seen (handheld uptime)", device.firstSeenUptimeMs.map { "\($0) ms" }))
        rows.append(("last seen (handheld uptime)", device.lastSeenUptimeMs.map { "\($0) ms" }))
        rows.append(("EAPOL", device.hasEAPOL.map { $0 ? "observed" : "no" }))
        return rows
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ARIAFrameCounterBar(counts: [
                    ("probe", device.probeCount), ("beacon", device.beaconCount),
                    ("data", device.dataCount), ("deauth", device.deauthCount),
                    ("mgmt", device.mgmtCount)
                ])
                ARIADeviceFieldsCard(rows: fields)
                ARIAFingerprintView(decode: device.decode)
                ARIAEvidenceSection(address: device.mac)
                ARIADecodeDetail(decode: device.decode)
                ARIAStoredRecordSection(source: .wifi, key: device.mac)
            }
            .padding()
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .navigationTitle(device.mac)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Labelled field table; fields the handheld did not send are listed as "not reported".
struct ARIADeviceFieldsCard: View {
    let rows: [(String, String?)]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline) {
                    Text(rows[i].0).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                    Spacer()
                    Text(rows[i].1 ?? "not reported").font(FinchTheme.monoSmall)
                        .foregroundStyle(rows[i].1 == nil ? FinchTheme.textSecondary : FinchTheme.textPrimary)
                        .finchCopyable(rows[i].1 ?? "")
                }
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).background(FinchCardBackground())
    }
}

struct ARIAEmptyRow: View {
    @Environment(AppModel.self) private var app
    var connected: Bool
    var body: some View {
        // Never present "nothing" while history is still arriving.
        let loading = !app.aria.history.loaded || app.aria.history.progressText != nil
        Text(loading ? "Loading capture history…" : connected ? "No observations yet." : "Not connected — join ARIA-Setup. No stored history yet.")
            .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            .listRowBackground(FinchTheme.surface)
    }
}
