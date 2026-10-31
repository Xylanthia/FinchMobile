import SwiftUI

/// Recognizes police body-worn / in-car camera equipment from identifiers the handheld already
/// reports. Every entry is a registry assignment (IEEE MA-L OUI, Bluetooth SIG company ID or
/// SIG 16-bit service UUID) held by a police-video maker. It names the maker, not a verified model:
/// Axon's OUI also covers its in-car (Fleet) cameras and docks.
enum ARIABodyCam {
    struct Match: Hashable {
        var maker: String
        var evidence: String     // which identifier matched
    }

    /// IEEE MA-L assignments (wifi_vendors.inc) to police body/in-car video makers.
    static let ouis: [String: String] = [
        "0025DF": "Axon",                      // Axon Enterprise, Inc.
        "001D96": "WatchGuard Video",          // Motorola Solutions police video (not WatchGuard Technologies firewalls)
        "0023BD": "Digital Ally",
        "0009BC": "Utility (BodyWorn)",        // Utility, Inc
        "0016ED": "Utility (BodyWorn)",
    ]
    /// Bluetooth SIG company IDs (manufacturer data).
    static let companyIDs: [UInt16: String] = [0x034D: "Axon"]   // TASER International, Inc.
    /// Bluetooth SIG member 16-bit service UUIDs.
    static let serviceUUIDs: [UInt16: String] = [0xFC81: "Axon"] // Axon Enterprise, Inc.

    static func match(mac: String?, companyID: String? = nil, advHex: String? = nil) -> Match? {
        if let m = matchMAC(mac) { return m }
        if let cid = parseID(companyID), let maker = companyIDs[cid] {
            return Match(maker: maker, evidence: String(format: "BLE company ID 0x%04X", cid))
        }
        if let uuid = serviceUUID(in: advHex), let maker = serviceUUIDs[uuid] {
            return Match(maker: maker, evidence: String(format: "BLE service UUID 0x%04X", uuid))
        }
        return nil
    }

    static func matchMAC(_ mac: String?) -> Match? {
        guard let mac else { return nil }
        let hex = mac.uppercased().filter(\.isHexDigit)
        guard hex.count >= 6 else { return nil }
        let oui = String(hex.prefix(6))
        // Locally administered (randomized) addresses carry no assigned OUI.
        guard let first = UInt8(oui.prefix(2), radix: 16), first & 0x02 == 0,
              let maker = ouis[oui] else { return nil }
        let pretty = stride(from: 0, to: 6, by: 2).map { i -> String in
            let s = oui.index(oui.startIndex, offsetBy: i)
            return String(oui[s..<oui.index(s, offsetBy: 2)])
        }.joined(separator: ":")
        return Match(maker: maker, evidence: "MAC OUI \(pretty)")
    }

    private static func parseID(_ text: String?) -> UInt16? {
        guard var t = text?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty else { return nil }
        if t.hasPrefix("0x") { t.removeFirst(2); return UInt16(t, radix: 16) }
        return UInt16(t) ?? UInt16(t, radix: 16)
    }

    /// First listed SIG service UUID we recognize, from raw advertising data (AD 0x02/0x03
    /// 16-bit UUID lists, AD 0x16 service data).
    static func serviceUUID(in advHex: String?) -> UInt16? {
        guard let advHex else { return nil }
        let hex = Array(advHex.filter(\.isHexDigit))
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var i = 0
        while i + 1 < hex.count {
            guard let b = UInt8(String(hex[i...i + 1]), radix: 16) else { return nil }
            bytes.append(b); i += 2
        }
        var offset = 0
        while offset < bytes.count {
            let length = Int(bytes[offset]); offset += 1
            guard length > 0, offset + length <= bytes.count else { break }
            let type = bytes[offset]
            let body = Array(bytes[(offset + 1)..<(offset + length)])
            switch type {
            case 0x02, 0x03:
                for j in stride(from: 0, to: body.count - 1, by: 2) {
                    let uuid = UInt16(body[j]) | UInt16(body[j + 1]) << 8
                    if serviceUUIDs[uuid] != nil { return uuid }
                }
            case 0x16 where body.count >= 2:
                let uuid = UInt16(body[0]) | UInt16(body[1]) << 8
                if serviceUUIDs[uuid] != nil { return uuid }
            default: break
            }
            offset += length
        }
        return nil
    }
}

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

extension ARIAWiFiDevice {
    var bodyCam: ARIABodyCam.Match? { ARIABodyCam.matchMAC(mac) ?? ARIABodyCam.matchMAC(bssid) }
}

extension ARIABLEDeviceRecord {
    var bodyCam: ARIABodyCam.Match? {
        ARIABodyCam.match(mac: address, companyID: companyID, advHex: decode?.rawHex)
    }
}
