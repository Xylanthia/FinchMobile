import Foundation
import Observation
import SwiftUI

/// The handheld's decoded capture evidence — the same per-frame intelligence its own screens
/// show (802.11 addressing / security / EAPOL handshake fields, BLE advertisement decode,
/// fingerprint attempts, CVE status). Pulled through /api/omni evidence pages, kept across
/// refreshes so frames the handheld has since evicted from its RAM ring stay visible here.
struct ARIAEvidenceFrame: Identifiable {
    enum Kind: String, CaseIterable {
        case wifi = "Wi-Fi frame"
        case eapol = "EAPOL handshake"
        case ble = "BLE advertisement"

        var command: String {
            switch self {
            case .wifi: return "./aria wifi frames"
            case .eapol: return "./aria wifi handshakes"
            case .ble: return "./aria evidence ble"
            }
        }
    }

    let id: String
    let kind: Kind
    let sequence: Int
    let timestampMs: Int?
    let rssi: Int?
    let channel: Int?
    /// Transmitter MAC (Wi-Fi) or advertiser address (BLE), uppercased.
    let address: String?
    let vendor: String?
    let record: [String: Any]
    let interpretations: [[String: Any]]

    init?(kind: Kind, record: [String: Any]) {
        guard let sequence = ARIAHistoryCodec.int(record["sequence"]) else { return nil }
        self.kind = kind
        self.sequence = sequence
        self.record = record
        timestampMs = ARIAHistoryCodec.int(record["timestamp_ms"])
        id = "\(kind.rawValue)-\(sequence)-\(timestampMs ?? 0)"
        rssi = ARIAHistoryCodec.int(record["rssi"])
        channel = ARIAHistoryCodec.int(record["channel"])
        let identifiers = record["identifiers"] as? [String: Any]
        address = ((record["address"] as? String) ?? (identifiers?["transmitter_mac"] as? String))?.uppercased()
        vendor = record["vendor"] as? String
        var intelligence: Any? = record["intelligence"]
        if let text = intelligence as? String, let data = text.data(using: .utf8) {
            intelligence = try? JSONSerialization.jsonObject(with: data)
        }
        interpretations = (intelligence as? [String: Any])?["interpretations"] as? [[String: Any]] ?? []
    }

    /// One-line summary of what the handheld decoded.
    var headline: String {
        let protocols = interpretations.compactMap { $0["protocol"] as? String }
        return protocols.isEmpty ? (record["decoded_status"] as? String ?? "undecoded") : protocols.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class ARIAEvidence {
    private(set) var frames: [ARIAEvidenceFrame] = []
    private(set) var lastError: String?
    private(set) var refreshing = false
    private(set) var lastRefresh: Date?
    private var byID: [String: ARIAEvidenceFrame] = [:]

    func frames(for address: String) -> [ARIAEvidenceFrame] {
        let key = address.uppercased()
        return frames.filter { $0.address == key }
    }

    /// Pages every evidence ring on the handheld (4 records per page, next_before cursor).
    func refresh(using client: ARIAClient) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        var errors: [String] = []
        for kind in ARIAEvidenceFrame.Kind.allCases {
            var before = 0
            for _ in 0..<256 {   // ring sizes are 128 / 64 / 8 frames; this only bounds a broken cursor
                do {
                    let page = try await client.omniJSON("\(kind.command) \(before) 4")
                    for record in page["frames"] as? [[String: Any]] ?? [] {
                        if let frame = ARIAEvidenceFrame(kind: kind, record: record) { byID[frame.id] = frame }
                    }
                    guard let next = ARIAHistoryCodec.int(page["next_before"]), next != before else { break }
                    before = next
                } catch {
                    errors.append("\(kind.rawValue): \(error.localizedDescription)")
                    break
                }
            }
        }
        frames = byID.values.sorted { ($0.timestampMs ?? 0, $0.sequence) > ($1.timestampMs ?? 0, $1.sequence) }
        lastError = errors.isEmpty ? nil : errors.joined(separator: " · ")
        lastRefresh = Date()
    }
}

// MARK: - Views

/// Renders any handheld JSON value completely: every key, nested object and array.
/// Long strings (hex, base64 waveforms) are shortened on screen but copy in full.
struct ARIAJSONTree: View {
    let value: Any
    var label: String? = nil
    var depth: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let dict = value as? [String: Any] {
                if let label { header(label, "\(dict.count) fields") }
                ForEach(dict.keys.sorted(), id: \.self) { key in
                    ARIAJSONTree(value: dict[key] ?? NSNull(), label: key, depth: depth + (label == nil ? 0 : 1))
                }
            } else if let array = value as? [Any] {
                if let label { header(label, "\(array.count) items") }
                ForEach(array.indices, id: \.self) { index in
                    ARIAJSONTree(value: array[index], label: "[\(index)]", depth: depth + 1)
                }
            } else {
                leaf(label ?? "value", Self.text(value))
            }
        }
        .padding(.leading, CGFloat(min(depth, 6)) * 10)
    }

    static func text(_ value: Any) -> String {
        switch value {
        case is NSNull: return "null"
        case let s as String: return s
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        default: return String(describing: value)
        }
    }

    private func header(_ key: String, _ detail: String) -> some View {
        Text("\(key) · \(detail)").font(.caption2.weight(.semibold)).foregroundStyle(FinchTheme.cyanDim)
    }

    private func leaf(_ key: String, _ text: String) -> some View {
        let shown = text.count > 600 ? String(text.prefix(300)) + "… (\(text.count) chars, copy for all)" : text
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            Spacer(minLength: 4)
            Text(shown).font(.system(.caption2, design: .monospaced)).foregroundStyle(FinchTheme.textPrimary)
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .finchCopyable(text)
    }
}

/// Full record as stored from the handheld (live snapshot or flash log), loaded on demand.
struct ARIAStoredRecordSection: View {
    @Environment(AppModel.self) private var app
    let source: ARIALogSource
    let key: String
    @State private var record: [String: Any]?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ALL HANDHELD FIELDS").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan)
            if let record {
                ARIAJSONTree(value: record)
            } else {
                Text(loaded ? "No stored record for this item yet." : "Loading…")
                    .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).background(FinchCardBackground())
        .task(id: key) {
            record = await app.aria.history.storedRecord(source, key)
            loaded = true
        }
    }
}

/// Decoded frames the handheld captured from one device.
struct ARIAEvidenceSection: View {
    @Environment(AppModel.self) private var app
    let address: String

    var body: some View {
        let frames = app.aria.evidence.frames(for: address)
        VStack(alignment: .leading, spacing: 8) {
            Text("DECODED FRAMES FROM HANDHELD · \(frames.count)").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan)
            if frames.isEmpty {
                Text("No retained frames from this address in the handheld's evidence rings.")
                    .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            }
            ForEach(frames) { frame in
                NavigationLink { ARIAEvidenceDetail(frame: frame) } label: { ARIAEvidenceRow(frame: frame) }
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).background(FinchCardBackground())
    }
}

struct ARIAEvidenceRow: View {
    let frame: ARIAEvidenceFrame
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(frame.kind.rawValue) #\(frame.sequence)").font(FinchTheme.mono).foregroundStyle(FinchTheme.textPrimary)
                Spacer()
                if let rssi = frame.rssi { Text("\(rssi) dBm").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary) }
            }
            Text(frame.headline).font(.caption2).foregroundStyle(FinchTheme.cyan)
            HStack(spacing: 8) {
                if let address = frame.address { Text(address).font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                if let channel = frame.channel { Text("ch \(channel)").font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
                if let vendor = frame.vendor { Text(vendor).font(.caption2).foregroundStyle(FinchTheme.textSecondary) }
            }
        }
    }
}

struct ARIAEvidenceDetail: View {
    let frame: ARIAEvidenceFrame
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ARIAEvidenceRow(frame: frame).padding().background(FinchCardBackground())
                ForEach(frame.interpretations.indices, id: \.self) { index in
                    let item = frame.interpretations[index]
                    VStack(alignment: .leading, spacing: 6) {
                        Text((item["protocol"] as? String ?? "Interpretation").uppercased())
                            .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan)
                        ARIAJSONTree(value: item)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading).background(FinchCardBackground())
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("ALL HANDHELD FIELDS").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan)
                    ARIAJSONTree(value: frame.record)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).background(FinchCardBackground())
            }
            .padding()
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .navigationTitle("\(frame.kind.rawValue) #\(frame.sequence)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Every decoded frame the handheld holds, newest first.
struct ARIAFramesView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: ARIAEvidenceFrame.Kind?

    var body: some View {
        let evidence = app.aria.evidence
        let shown = evidence.frames.filter { filter == nil || $0.kind == filter }
        List {
            Section {
                Picker("Kind", selection: $filter) {
                    Text("All").tag(ARIAEvidenceFrame.Kind?.none)
                    ForEach(ARIAEvidenceFrame.Kind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(ARIAEvidenceFrame.Kind?.some(kind))
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("\(shown.count) decoded frames").font(FinchTheme.monoSmall)
                    Spacer()
                    if evidence.refreshing { ProgressView().controlSize(.small) }
                    else if let at = evidence.lastRefresh {
                        Text(at.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                    }
                }
                if let error = evidence.lastError {
                    Text(error).font(.caption2).foregroundStyle(FinchTheme.warn)
                }
            }
            .listRowBackground(FinchTheme.surface)
            ForEach(shown) { frame in
                NavigationLink { ARIAEvidenceDetail(frame: frame) } label: { ARIAEvidenceRow(frame: frame) }
                    .listRowBackground(FinchTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle("Decoded frames")
        .refreshable { await app.aria.refreshEvidence() }
    }
}
