import Foundation

enum ARIAListScope: String, CaseIterable, Identifiable {
    case live = "Live now", total = "Total seen"
    var id: String { rawValue }
    func includes(live: Int, total: Int) -> Bool { self == .live ? live > 0 : total > 0 }
}

enum ARIAListFilter {
    static func matches(_ query: String, fields: [String?], decode: ARIADecodeEnvelope? = nil) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let fingerprints = (decode?.fingerprintAttempts ?? []).flatMap { [$0.vendor, $0.modelCandidate] }
        let decoded = (decode?.decodedFields ?? [:]).filter {
            ["name", "vendor", "manufacturer", "model", "mac", "address", "bssid", "ssid", "id"].contains($0.key.lowercased())
        }.map { Optional($0.value) }
        return (fields + fingerprints + decoded).compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
    }
    static func matches(_ query: String, _ device: ARIABLEDeviceRecord) -> Bool {
        matches(query, fields: [device.name, device.vendor, device.address, device.bssid], decode: device.decode)
    }
    static func matches(_ query: String, _ device: ARIAWiFiDevice) -> Bool {
        matches(query, fields: [device.ssid, device.vendor, device.mac, device.bssid], decode: device.decode)
    }
    static func matches(_ query: String, _ capture: ARIASubGHzCapture) -> Bool {
        matches(query, fields: [capture.detail], decode: capture.decode)
    }
}
