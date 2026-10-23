import SwiftUI

struct ARIASubGHzView: View {
    @Environment(AppModel.self) private var app
    @State private var outcome: String?

    var body: some View {
        let captures = app.aria.session.subghz
        List {
            if captures.isEmpty {
                ARIAEmptyRow(connected: app.aria.connection.state.isConnected)
            }
            ForEach(captures) { c in
                NavigationLink {
                    ARIASubGHzDetail(capture: c)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(c.frequencyMHz.map { String(format: "%.3f MHz", $0) } ?? "— MHz")
                                .font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                            Spacer()
                            if let r = c.rssi { Text("\(r) dBm").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary) }
                        }
                        HStack(spacing: 8) {
                            if let p = c.pulseCount { Text("\(p)p").font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                            if let d = c.durationUS { Text("\(d)us").font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                        }
                        // Honest status badge, verbatim (§3.4) — never normalize failure states away.
                        if let detail = c.detail {
                            SubGHzStatusBadge(detail: detail)
                        }
                    }
                }
                .listRowBackground(FinchTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle("Sub-GHz")
        .overlay(alignment: .bottom) {
            if let outcome {
                Text(outcome).font(FinchTheme.monoSmall).padding(10).background(FinchCardBackground()).padding()
            }
        }
    }
}

struct SubGHzStatusBadge: View {
    var detail: String
    var body: some View {
        let up = detail.uppercased()
        let bad = up.contains("INCOMPLETE") || up.contains("ERROR") || up.contains("MAX-PULSES")
        Text(detail)
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill((bad ? FinchTheme.warn : FinchTheme.cyan).opacity(0.18)))
            .foregroundStyle(bad ? FinchTheme.warn : FinchTheme.cyan)
    }
}

struct ARIASubGHzDetail: View {
    @Environment(AppModel.self) private var app
    let capture: ARIASubGHzCapture
    @State private var outcome: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let detail = capture.detail { SubGHzStatusBadge(detail: detail) }
                ARIADecodeDetail(decode: capture.decode)

                Button {
                    Task {
                        switch await app.aria.replaySubGHz(capture) {
                        case .success: outcome = "replay sent"
                        case .unknown(let m): outcome = "UNKNOWN — \(m)"
                        case .failed(let m): outcome = "FAILED — \(m)"
                        }
                    }
                } label: {
                    Label("Replay capture", systemImage: "arrow.clockwise.circle")
                        .font(FinchTheme.mono)
                        .frame(maxWidth: .infinity).padding()
                        .background(FinchCardBackground())
                }
                .disabled(!app.aria.connection.state.isConnected)
                .opacity(app.aria.connection.state.isConnected ? 1 : 0.4)

                if let outcome {
                    Text(outcome).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
                }
            }
            .padding()
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .navigationTitle("seq \(capture.sequence)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
