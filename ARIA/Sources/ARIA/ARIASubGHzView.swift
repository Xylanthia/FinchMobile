import SwiftUI

struct ARIASubGHzView: View {
    @Environment(AppModel.self) private var app
    @State private var outcome: String?

    var body: some View {
        let captures = app.aria.history.subghz
        List {
            Section {
                ARIAHistoryBanner()
                ARIASourceCounts(source: .subghz)
            }
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
    @State private var prepared: ARIAClient.ReplayPreparation?
    @State private var busy = false

    private func prepare() async {
        busy = true; defer { busy = false }
        outcome = nil
        switch await app.aria.prepareReplay(capture) {
        case .success(let prep): prepared = prep
        case .failure(let e): outcome = "FAILED — \(e.message)"
        }
    }

    private func transmit(_ prep: ARIAClient.ReplayPreparation) async {
        busy = true; defer { busy = false }
        prepared = nil
        // The handheld voids the token after 60 s; say so instead of sending a dead token.
        guard Date().timeIntervalSince(prep.preparedAt) < 58 else {
            outcome = "Preparation expired (60 s). Tap Replay capture again."
            await app.aria.cancelReplay()
            return
        }
        switch await app.aria.confirmReplay(prep) {
        case .success: outcome = app.aria.lastFireOutput ?? "Replay sent."
        case .unknown(let m): outcome = "UNKNOWN (connection dropped; it may have transmitted) — \(m)"
        case .failed(let m): outcome = "FAILED — \(m)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let detail = capture.detail { SubGHzStatusBadge(detail: detail) }
                ARIADecodeDetail(decode: capture.decode)
                ARIAStoredRecordSection(source: .subghz, key: capture.id)

                if let prep = prepared {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ready to transmit. Nothing has been sent yet.")
                            .font(FinchTheme.mono).foregroundStyle(FinchTheme.warn)
                        Text(prep.summary)
                            .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
                            .textSelection(.enabled)
                        HStack(spacing: 10) {
                            Button {
                                Task { await transmit(prep) }
                            } label: {
                                Label("Transmit once", systemImage: "dot.radiowaves.right")
                                    .font(FinchTheme.mono).frame(maxWidth: .infinity).padding()
                                    .background(FinchCardBackground())
                            }
                            Button {
                                prepared = nil
                                outcome = "Cancelled. Nothing transmitted."
                                Task { await app.aria.cancelReplay() }
                            } label: {
                                Text("Cancel").font(FinchTheme.mono).padding()
                                    .background(FinchCardBackground())
                            }
                        }
                        .disabled(busy || !app.aria.connection.state.isConnected)
                    }
                    .padding().background(FinchCardBackground())
                } else {
                    Button {
                        Task { await prepare() }
                    } label: {
                        Label(busy ? "Preparing…" : "Replay capture", systemImage: "arrow.clockwise.circle")
                            .font(FinchTheme.mono)
                            .frame(maxWidth: .infinity).padding()
                            .background(FinchCardBackground())
                    }
                    .disabled(busy || !app.aria.connection.state.isConnected)
                    .opacity(app.aria.connection.state.isConnected ? 1 : 0.4)
                }

                if let outcome {
                    Text(outcome).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .navigationTitle("seq \(capture.sequence)")
        .onDisappear {
            if prepared != nil { Task { await app.aria.cancelReplay() } }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
