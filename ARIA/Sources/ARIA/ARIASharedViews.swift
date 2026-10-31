import SwiftUI

// MARK: - Connection banner (§2)

struct ARIAConnectionBanner: View {
    var state: ARIAConnectionState
    var lastPoll: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 10, height: 10)
                Text(title).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textPrimary)
                Spacer()
                if let lastPoll {
                    Text("last: \(lastPoll.formatted(date: .omitted, time: .standard))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(FinchTheme.textSecondary)
                }
            }
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            }
            if state == .notOnARIANetwork, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Join ARIA-Setup Wi-Fi →", destination: url)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.cyan)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FinchCardBackground())
        .padding(.horizontal)
    }

    private var dotColor: Color {
        switch state {
        case .connected: return FinchTheme.cyan
        case .deviceUnreachable: return FinchTheme.warn
        case .notOnARIANetwork: return FinchTheme.danger
        }
    }
    private var title: String {
        switch state {
        case .connected: return "CONNECTED — live"
        case .deviceUnreachable: return "ARIA DEVICE NOT RESPONDING"
        case .notOnARIANetwork: return "NOT ON ARIA NETWORK"
        }
    }
    private var detail: String? {
        switch state {
        case .connected: return nil
        case .deviceUnreachable: return "On a network, but the device timed out. Data below is not live."
        case .notOnARIANetwork: return "Join the ARIA-Setup Wi-Fi AP to control and view the device."
        }
    }
}

// MARK: - Fingerprint presentation (§1.4) — matches Glass Fabric's bar.

struct ARIAFingerprintView: View {
    var decode: ARIADecodeEnvelope?

    var body: some View {
        // §1.4.4 — firmware not emitting fingerprint data is an explicit state, not empty fields.
        guard let decode, decode.hasFingerprintData, let fp = decode.bestFingerprint else {
            return AnyView(
                Text("no fingerprint match")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
            )
        }

        let vendor = fp.vendor

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(vendor ?? "unknown vendor")
                        .font(FinchTheme.monoSmall.weight(.semibold))
                        .foregroundStyle(FinchTheme.textPrimary)
                    if let model = fp.modelCandidate, !model.isEmpty {
                        Text("· \(model)").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
                    }
                    Spacer()
                    ConfidenceTag(confidence: fp.confidence, hasModel: fp.modelCandidate?.isEmpty == false)
                }
                if let cls = fp.deviceClass, !cls.isEmpty {
                    Text(cls.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(FinchTheme.cyan)
                }
            }
        )
    }
}

/// Low-confidence vendor-only reads differently from high-confidence model+CVE (§1.4.2).
/// No confidence = a vendor-only OUI/company lookup, labelled as such (not "LOW 0%").
private struct ConfidenceTag: View {
    var confidence: Double?
    var hasModel: Bool

    var body: some View {
        let strong = (confidence ?? 0) >= 0.8 && hasModel
        Text(confidence == nil ? "OUI VENDOR" : strong ? "HIGH \(pct)" : "LOW \(pct)")
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                Capsule().fill((strong ? FinchTheme.cyan : FinchTheme.warn).opacity(0.2))
            )
            .foregroundStyle(strong ? FinchTheme.cyan : FinchTheme.warn)
    }
    private var pct: String { "\(Int((confidence ?? 0) * 100))%" }
}

// MARK: - Frame counter bar (shared by Wi-Fi & BLE, §3.2/§3.3)

struct ARIAFrameCounterBar: View {
    var counts: [(String, Int?)]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(counts.indices, id: \.self) { i in
                let (label, value) = counts[i]
                VStack(spacing: 2) {
                    Text(value.map(String.init) ?? "—")
                        .font(FinchTheme.monoSmall.weight(.semibold))
                        .foregroundStyle(label == "deauth" && (value ?? 0) > 0 ? FinchTheme.danger : FinchTheme.textPrimary)
                    Text(label).font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(FinchTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .background(FinchCardBackground())
    }
}

// MARK: - Raw/decoded detail (§3.2/§3.3/§3.4)

struct ARIADecodeDetail: View {
    var decode: ARIADecodeEnvelope?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let decode {
                if let status = decode.decodedStatus {
                    statusRow("decoded_status", status)
                }
                if let avail = decode.rawAvailability {
                    statusRow("raw_availability", avail)   // e.g. EVICTED_OR_CLEARED — shown, not hidden
                }
                if let ver = decode.verificationStatus {
                    statusRow("verification_status", ver)
                }
                if let reason = decode.decodedReason, !reason.isEmpty {
                    statusRow("decoded_reason", reason)
                }
                if let fields = decode.decodedFields, !fields.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("decoded_fields").font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                        ForEach(fields.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            Text("\(k): \(v)").font(FinchTheme.monoSmall).finchCopyable(v)
                        }
                    }
                }
                hexBlock("raw_hex", decode.rawHex)
                hexBlock("decoded_hex", decode.decodedHex)
            } else {
                Text("no decode data").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            }
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            Spacer()
            Text(value).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textPrimary).finchCopyable(value)
        }
    }

    @ViewBuilder
    private func hexBlock(_ label: String, _ hex: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            if let hex, !hex.isEmpty {
                Text(hex)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(FinchTheme.textPrimary)
                    .textSelection(.enabled)
                    .finchCopyable(hex)
            } else {
                Text("(empty)").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
            }
        }
    }
}

// MARK: - Live vs total (one canonical pair per source, labelled identically everywhere)

/// "Live now" = heard by the handheld in the last 60 s (Sub-GHz: still in its RAM ring).
/// "Total seen" = every distinct device/capture in the persistent history, in range or not.
/// Total never decrements when something leaves range, and Total ≥ Live always.
struct ARIASourceCounts: View {
    @Environment(AppModel.self) private var app
    let source: ARIALogSource

    var body: some View {
        let history = app.aria.history
        let connected = app.aria.connection.state.isConnected
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(source == .subghz ? "in handheld RAM now" : "live now")
                    .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                Text(connected ? history.liveCount(source).formatted() : "—")
                    .font(FinchTheme.monoSmall.weight(.semibold)).foregroundStyle(FinchTheme.cyan)
                Spacer()
                Text("total seen").font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                Text(history.totalText(source))
                    .font(FinchTheme.monoSmall.weight(.semibold)).foregroundStyle(FinchTheme.textPrimary)
            }
            if let logged = history.handheldTotal(source) {
                Text("handheld flash log: \(logged.formatted()) records")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(FinchTheme.textSecondary)
            }
            if case .unavailable(let why) = history.backfill[source] {
                Text("history unavailable · \(why)").font(.caption2).foregroundStyle(FinchTheme.warn)
            }
        }
        .listRowBackground(FinchTheme.surface)
    }
}

/// Non-blocking backfill progress ("Loading capture history: 1,840 / 3,112").
struct ARIAHistoryBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let text = app.aria.history.progressText {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textPrimary)
            }
            .listRowBackground(FinchTheme.surface)
        }
    }
}

/// Marks a history row that is no longer being heard. The row itself is never removed.
struct ARIARangeTag: View {
    @Environment(AppModel.self) private var app
    let source: ARIALogSource
    let id: String

    var body: some View {
        if !app.aria.history.isLive(source, id) {
            let last = app.aria.history.lastSeen(source, id)
            Text("NOT IN RANGE" + (last.map { " · last \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(FinchTheme.textSecondary)
        }
    }
}
