import SwiftUI

struct ARIAWiFiView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let devices = app.aria.session.wifi
        List {
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ARIAFrameCounterBar(counts: [
                    ("probe", device.probeCount), ("beacon", device.beaconCount),
                    ("data", device.dataCount), ("deauth", device.deauthCount),
                    ("mgmt", device.mgmtCount)
                ])
                ARIAFingerprintView(decode: device.decode)
                ARIADecodeDetail(decode: device.decode)
            }
            .padding()
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .navigationTitle(device.mac)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ARIAEmptyRow: View {
    var connected: Bool
    var body: some View {
        Text(connected ? "No observations yet." : "Not connected — join ARIA-Setup.")
            .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            .listRowBackground(FinchTheme.surface)
    }
}
