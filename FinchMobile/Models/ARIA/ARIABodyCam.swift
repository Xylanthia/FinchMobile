import SwiftUI

struct ARIABodyCamBadge: View {
    let match: ARIABodyCam.Match
    var body: some View {
        Label("POLICE BODY CAM · \(match.maker)", systemImage: "video.fill")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(FinchTheme.warn.opacity(0.2)))
            .foregroundStyle(FinchTheme.warn)
    }
}

struct ARIABodyCamCoverageCard: View {
    @Environment(AppModel.self) private var app

    private struct Candidate: Identifiable {
        let id: String
        let match: ARIABodyCam.Match
        let live: Bool
    }

    private var candidates: [Candidate] {
        let history = app.aria.history
        let wifi = history.wifi.compactMap { device -> Candidate? in
            guard let match = device.bodyCam else { return nil }
            return Candidate(id: "wifi:\(device.mac)", match: match, live: history.isLive(.wifi, device.mac))
        }
        let ble = history.ble.compactMap { device -> Candidate? in
            guard let match = device.bodyCam else { return nil }
            return Candidate(id: "ble:\(device.address)", match: match, live: history.isLive(.ble, device.address))
        }
        return (wifi + ble).sorted { $0.id < $1.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("BODY CAMERA COVERAGE", systemImage: "video.fill")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(FinchTheme.warn)
                Spacer()
                Text("\(candidates.filter(\.live).count) live · \(candidates.count) session").font(FinchTheme.monoSmall)
            }
            Text("Possible maker identifiers; a match does not confirm a body camera.")
                .font(.system(size: 9)).foregroundStyle(FinchTheme.textSecondary)
            if candidates.isEmpty {
                Text("No supported body-camera maker identifiers seen this session.")
                    .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            } else {
                ForEach(candidates.prefix(4)) { item in
                    HStack {
                        Text(item.match.maker).font(FinchTheme.monoSmall)
                        Spacer()
                        Text(item.live ? "LIVE" : "SESSION")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(item.live ? FinchTheme.cyan : FinchTheme.textSecondary)
                        Text(item.match.evidence).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(FinchTheme.textSecondary)
                    }
                }
                if candidates.count > 4 {
                    Text("+\(candidates.count - 4) more in Wi-Fi / BLE lists")
                        .font(.system(size: 9)).foregroundStyle(FinchTheme.textSecondary)
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(FinchCardBackground())
        .accessibilityElement(children: .contain)
    }
}

extension ARIAWiFiDevice {
    var bodyCam: ARIABodyCam.Match? { ARIABodyCam.matchMAC(mac) ?? ARIABodyCam.matchMAC(bssid) }
}

extension ARIABLEDeviceRecord {
    var bodyCam: ARIABodyCam.Match? {
        ARIABodyCam.match(mac: address, companyID: companyID, advHex: decode?.rawHex)
    }
}
