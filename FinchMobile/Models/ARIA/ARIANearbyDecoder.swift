import Foundation
import Observation
import SwiftUI

// Nearby (the phone's own BLE scan) identified by the ARIA handheld's decoder and
// fingerprinter instead of iOS-side heuristics. Each advertisement is rebuilt into on-air AD
// structures and sent to GET /api/decode/ble on the handheld, which runs the same
// universal decoder + fingerprinter it uses for its own captures.

extension BLEDevice {
    /// AD structures rebuilt from what CoreBluetooth reported, in on-air byte format. iOS does
    /// not expose the raw PDU, so this holds exactly the fields iOS parsed — nothing invented.
    var reconstructedADHex: String {
        var out: [UInt8] = []
        func add(_ type: UInt8, _ data: [UInt8]) {
            let body = Array(data.prefix(254))
            guard !body.isEmpty || type == 0x01 else { return }
            out.append(UInt8(body.count + 1)); out.append(type); out.append(contentsOf: body)
        }
        if let flags = advertisementFlags { add(0x01, [flags]) }
        if let name = localName, !name.isEmpty { add(0x09, Array(name.utf8)) }
        if let tx = txPower { add(0x0A, [UInt8(bitPattern: Int8(clamping: tx))]) }
        var u16: [UInt8] = [], u32: [UInt8] = [], u128: [UInt8] = []
        for uuid in serviceUUIDs + overflowServiceUUIDs {
            let bytes = Self.uuidBytesLE(uuid)
            switch bytes.count { case 2: u16 += bytes; case 4: u32 += bytes; case 16: u128 += bytes; default: break }
        }
        add(0x03, u16); add(0x05, u32); add(0x07, u128)
        var s16: [UInt8] = [], s128: [UInt8] = []
        for uuid in solicitedServiceUUIDs {
            let bytes = Self.uuidBytesLE(uuid)
            if bytes.count == 2 { s16 += bytes } else if bytes.count == 16 { s128 += bytes }
        }
        add(0x14, s16); add(0x15, s128)
        for (uuid, hex) in serviceData.sorted(by: { $0.key < $1.key }) {
            let id = Self.uuidBytesLE(uuid)
            let type: UInt8 = id.count == 2 ? 0x16 : id.count == 4 ? 0x20 : 0x21
            if !id.isEmpty { add(type, id + Self.bytes(hex)) }
        }
        if let raw = manufacturerDataRawHex { add(0xFF, Self.bytes(raw)) }
        return out.map { String(format: "%02X", $0) }.joined()
    }

    static func bytes(_ hex: String) -> [UInt8] {
        let clean = hex.filter(\.isHexDigit)
        var result: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex, let next = clean.index(index, offsetBy: 2, limitedBy: clean.endIndex) {
            if let b = UInt8(clean[index..<next], radix: 16) { result.append(b) }
            index = next
        }
        return result
    }

    /// CBUUID string → little-endian on-air bytes (16/32/128-bit).
    static func uuidBytesLE(_ uuid: String) -> [UInt8] {
        let hex = uuid.filter(\.isHexDigit)
        guard [4, 8, 32].contains(hex.count) else { return [] }
        return Array(bytes(hex).reversed())
    }
}

@MainActor
@Observable
final class ARIANearbyDecoder {
    struct Decode {
        let response: [String: Any]
        let name: String?
        let vendor: String?
        let manufacturer: String?
        let deviceClass: String?
        let model: String?
        let confidence: String?
        let beacon: String?
        let protocols: [String]
        let services: String?
    }

    private(set) var decoded: [String: Decode] = [:]
    private(set) var unsupported = false
    private(set) var lastError: String?
    private var queue: [String] = []
    private var queued = Set<String>()
    private var running = false

    func decode(for device: BLEDevice) -> Decode? { decoded[device.reconstructedADHex] }

    /// Queues every not-yet-decoded advertisement payload; one request at a time so the
    /// handheld's web server is never flooded.
    func submit(_ devices: [BLEDevice], client: ARIAClient) {
        guard !unsupported else { return }
        for device in devices {
            let hex = device.reconstructedADHex
            guard !hex.isEmpty, decoded[hex] == nil, !queued.contains(hex) else { continue }
            queued.insert(hex); queue.append(hex)
        }
        guard !running, !queue.isEmpty else { return }
        running = true
        Task { await self.drain(client) }
    }

    private func drain(_ client: ARIAClient) async {
        defer { running = false }
        while !queue.isEmpty {
            let hex = queue.removeFirst()
            do {
                let response = try await client.decodeBLE(advHex: hex)
                decoded[hex] = Self.parse(response)
                lastError = nil
            } catch let failure as ARIAClient.Failure where failure.statusCode == 404 {
                unsupported = true
                lastError = "Handheld firmware has no /api/decode/ble — flash the current ARIA build."
                queue.removeAll(); queued.removeAll()
                return
            } catch {
                lastError = error.localizedDescription
                queued.remove(hex)   // retried on the next submit
                return
            }
        }
    }

    static func parse(_ r: [String: Any]) -> Decode {
        let intelligence = r["intelligence"] as? [String: Any] ?? [:]
        let interpretations = intelligence["interpretations"] as? [[String: Any]] ?? []
        let ble = interpretations.first { ($0["protocol"] as? String) == "Bluetooth Low Energy Advertising" }
        let fields = ble?["decoded_fields"] as? [String: Any] ?? [:]
        let manufacturer = (ble?["manufacturer"] as? String).flatMap { $0 == "UNKNOWN" ? nil : $0 }
        let beacon = (fields["decoded_beacon"] as? String)?.components(separatedBy: "\n").first
        let protocols = interpretations.compactMap { $0["protocol"] as? String }
            .filter { $0 != "Bluetooth Low Energy Advertising" }
        return Decode(response: r,
                      name: fields["local_name"] as? String,
                      vendor: r["vendor"] as? String,
                      manufacturer: manufacturer,
                      deviceClass: r["device_class"] as? String,
                      model: r["model_candidate"] as? String,
                      confidence: r["confidence"] as? String,
                      beacon: beacon,
                      protocols: protocols,
                      services: fields["service_uuids"] as? String)
    }
}

/// The handheld's own capture of the same advertisement (matched on identical
/// manufacturer or service-data bytes) — gives the address and address type iOS hides.
struct ARIAAddressMatch {
    let address: String
    let addressType: String?
    let vendor: String?
}

extension ARIAEvidence {
    func addressMatch(for device: BLEDevice) -> ARIAAddressMatch? {
        var needles: [String] = []
        if let raw = device.manufacturerDataRawHex { needles.append(raw.filter(\.isHexDigit).uppercased()) }
        for hex in device.serviceData.values { needles.append(hex.filter(\.isHexDigit).uppercased()) }
        needles = needles.filter { $0.count >= 8 }   // ≥ 4 bytes, so short common payloads don't false-match
        guard !needles.isEmpty else { return nil }
        for frame in frames where frame.kind == .ble {
            guard let address = frame.address,
                  let hex = (frame.record["hex"] as? String ?? frame.record["raw_hex"] as? String)?.uppercased() else { continue }
            if needles.contains(where: { hex.contains($0) }) {
                let identifiers = frame.record["identifiers"] as? [String: Any]
                return ARIAAddressMatch(address: address,
                                        addressType: (frame.record["address_type"] ?? identifiers?["address_type"]) as? String,
                                        vendor: frame.vendor)
            }
        }
        return nil
    }
}

extension ARIACoordinator {
    /// Identity for a phone-scanned BLE device: the ARIA decoder/fingerprinter result when the
    /// handheld has decoded it, the phone's own classification otherwise.
    func nearbyIdentity(for device: BLEDevice) -> BLEFriendlyIdentity {
        let phone = device.friendly
        guard let d = nearby.decode(for: device) else { return phone }
        let match = evidence.addressMatch(for: device)
        let vendor = d.vendor ?? d.manufacturer ?? match?.vendor
        let kind = d.deviceClass ?? d.model ?? d.beacon ?? d.protocols.first
        let decodedKinds = ([d.beacon] + d.protocols.map(Optional.some)).compactMap { $0 }
        var evidenceLines = ["ARIA decoder: " + (decodedKinds.isEmpty ? "BLE advertisement" : decodedKinds.joined(separator: ", "))]
        if let v = vendor { evidenceLines.append("ARIA fingerprint: \(v)" + (d.confidence.map { " (\($0))" } ?? "")) }
        if let m = match { evidenceLines.append("Handheld capture: \(m.address)" + (m.addressType.map { " \($0)" } ?? "")) }
        if let s = d.services { evidenceLines.append("Services: \(s)") }

        let title: String
        if let name = device.broadcastName ?? d.name {
            title = name
        } else if let vendor, let kind {
            title = "\(BLESIGTables.shortName(vendor)) · \(kind)"
        } else if let vendor {
            title = "\(BLESIGTables.shortName(vendor)) device"
        } else if let kind {
            title = kind
        } else if !phone.deviceType.hasPrefix("Unknown") {
            title = phone.title   // phone decode found something the AD bytes alone don't name
        } else if let match {
            title = "BLE \(match.address)"
        } else {
            title = d.services.map { "BLE · services \($0)" } ?? "BLE advertiser · no ID fields in ad"
        }
        var identity = phone
        identity.title = title
        identity.deviceType = kind.map { "ARIA: \($0)" } ?? (vendor != nil ? "ARIA: vendor match" : "ARIA: decoded")
        identity.summary = evidenceLines.joined(separator: " · ")
        identity.confidence = d.confidence ?? (vendor != nil ? "ARIA vendor" : "ARIA decode")
        identity.evidence = evidenceLines + phone.evidence
        return identity
    }
}

/// ARIA decoder + fingerprinter output for one phone-scanned device, shown in full.
struct ARIANearbyDecodeBlock: View {
    @Environment(AppModel.self) private var app
    let device: BLEDevice

    var body: some View {
        let nearby = app.aria.nearby
        VStack(alignment: .leading, spacing: 6) {
            Text("ARIA DECODER + FINGERPRINTER").font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.cyan)
            if let match = app.aria.evidence.addressMatch(for: device) {
                Text("Handheld captured this advertisement from \(match.address)\(match.addressType.map { " (\($0))" } ?? "")\(match.vendor.map { " · \($0)" } ?? "")")
                    .font(.caption2).foregroundStyle(FinchTheme.textPrimary).finchCopyable(match.address)
            }
            if let decode = nearby.decode(for: device) {
                ARIAJSONTree(value: decode.response)
            } else if nearby.unsupported || nearby.lastError != nil {
                Text(nearby.lastError ?? "Handheld decoder unavailable").font(.caption2).foregroundStyle(FinchTheme.warn)
            } else if !app.aria.connection.state.isConnected {
                Text("Join ARIA-Setup Wi-Fi: this advertisement is then decoded and fingerprinted by the handheld.")
                    .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            } else {
                Text("Queued for the handheld decoder…").font(.caption2).foregroundStyle(FinchTheme.textSecondary)
            }
            Text("Advertisement bytes sent: \(device.reconstructedADHex.isEmpty ? "(none reported by iOS)" : device.reconstructedADHex)")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(FinchTheme.textSecondary)
                .finchCopyable(device.reconstructedADHex)
        }
        .padding(.vertical, 4)
    }
}
