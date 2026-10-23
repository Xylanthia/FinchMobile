import SwiftUI

struct ARIABLEView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let devices = app.aria.session.ble
        List {
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
                        HStack(spacing: 8) {
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ARIAFingerprintView(decode: device.decode)
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
            }
            .padding()
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .navigationTitle(device.address)
        .navigationBarTitleDisplayMode(.inline)
    }
}
