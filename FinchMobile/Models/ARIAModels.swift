import Foundation

// MARK: - Canonical observation schema
// Mirrors ARIA_FINAL_FORENSIC_SPEC.md field names so firmware and phone stay in sync.
// raw_hex / decoded_hex / decoded_fields / raw_availability / decoded_status /
// decoded_reason / verification_status are all carried verbatim — never normalized away.

/// A fingerprint attempt as emitted per observation (spec §M.6).
struct ARIAFingerprintAttempt: Codable, Hashable {
    var vendor: String?
    var deviceClass: String?
    var modelCandidate: String?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case vendor
        case deviceClass = "device_class"
        case modelCandidate = "model_candidate"
        case confidence
    }
}

/// Shared decode/verification envelope present on every band's observation.
struct ARIADecodeEnvelope: Codable, Hashable {
    var rawHex: String?
    var decodedHex: String?
    var decodedFields: [String: String]?
    var rawAvailability: String?      // e.g. "AVAILABLE", "EVICTED_OR_CLEARED"
    var decodedStatus: String?        // e.g. "DECODED", "INCOMPLETE", "ERROR"
    var decodedReason: String?        // why decode failed, when it did
    var verificationStatus: String?
    var fingerprintAttempts: [ARIAFingerprintAttempt]?

    enum CodingKeys: String, CodingKey {
        case rawHex = "raw_hex"
        case decodedHex = "decoded_hex"
        case decodedFields = "decoded_fields"
        case rawAvailability = "raw_availability"
        case decodedStatus = "decoded_status"
        case decodedReason = "decoded_reason"
        case verificationStatus = "verification_status"
        case fingerprintAttempts = "fingerprint_attempts"
    }

    /// Best fingerprint attempt by confidence, if any was emitted.
    var bestFingerprint: ARIAFingerprintAttempt? {
        fingerprintAttempts?.max(by: { ($0.confidence ?? 0) < ($1.confidence ?? 0) })
    }

    /// True only when firmware actually emitted fingerprint data (spec §1.4.4).
    var hasFingerprintData: Bool {
        guard let a = fingerprintAttempts else { return false }
        return !a.isEmpty
    }
}

// MARK: - Band records

struct ARIAWiFiDevice: Codable, Hashable, Identifiable {
    var mac: String
    var ssid: String?
    var vendor: String?          // OUI-resolved
    var rssi: Int?
    var encryption: String?
    var seenCount: Int?
    var probeCount: Int?
    var beaconCount: Int?
    var dataCount: Int?
    var deauthCount: Int?
    var mgmtCount: Int?
    var hasEAPOL: Bool?
    var decode: ARIADecodeEnvelope?

    var id: String { mac }

    enum CodingKeys: String, CodingKey {
        case mac, ssid, vendor, rssi, encryption
        case seenCount = "seen_count"
        case probeCount = "probe_count"
        case beaconCount = "beacon_count"
        case dataCount = "data_count"
        case deauthCount = "deauth_count"
        case mgmtCount = "mgmt_count"
        case hasEAPOL = "eapol"
        case decode
    }
}

struct ARIABLEDeviceRecord: Codable, Hashable, Identifiable {
    var address: String
    var name: String?
    var rssi: Int?
    var companyID: String?        // manufacturer company ID
    var seenCount: Int?
    var adStructures: [String: String]?
    var decode: ARIADecodeEnvelope?

    var id: String { address }

    enum CodingKeys: String, CodingKey {
        case address, name, rssi
        case companyID = "company_id"
        case seenCount = "seen_count"
        case adStructures = "ad_structures"
        case decode
    }
}

struct ARIASubGHzCapture: Codable, Hashable, Identifiable {
    var sequence: Int
    var boot: Int?
    var frequencyMHz: Double?
    var rssi: Int?
    var pulseCount: Int?
    var durationUS: Int?
    var detail: String?          // honest status string, shown verbatim (e.g. "INCOMPLETE … MAX-PULSES")
    var decode: ARIADecodeEnvelope?

    var id: String { "\(sequence)-\(boot ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case sequence, boot, rssi, detail, decode
        case frequencyMHz = "frequency_mhz"
        case pulseCount = "pulse_count"
        case durationUS = "duration_us"
    }

    /// Replay endpoint path (raw_capture_ref), per transport §1.
    var replayPath: String {
        "/api/subghz/raw?sequence=\(sequence)&boot=\(boot ?? 0)"
    }
}

/// Only VALIDATED Remote ID records. GENERIC_RF observations never become these (spec §3.5).
struct ARIAUASRecord: Codable, Hashable, Identifiable {
    var uasID: String
    var idType: String?
    var uaType: String?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var speed: Double?
    var operatorID: String?
    var operatorLatitude: Double?
    var operatorLongitude: Double?
    var decoderProvenance: String?

    var id: String { uasID }

    enum CodingKeys: String, CodingKey {
        case uasID = "uas_id"
        case idType = "id_type"
        case uaType = "ua_type"
        case latitude, longitude, altitude, speed
        case operatorID = "operator_id"
        case operatorLatitude = "operator_lat"
        case operatorLongitude = "operator_lon"
        case decoderProvenance = "decoder_provenance"
    }
}

struct ARIARFIDTag: Codable, Hashable, Identifiable {
    var uid: String
    var atqa: String?
    var sak: String?
    var tagType: String?
    var readStatus: String?

    var id: String { uid }

    enum CodingKeys: String, CodingKey {
        case uid, atqa, sak
        case tagType = "tag_type"
        case readStatus = "read_status"
    }
}

// MARK: - Session summary / health

struct ARIASessionSummary: Codable, Hashable {
    var uptimeSeconds: Int?
    var wifiCount: Int?
    var bleCount: Int?
    var subghzCount: Int?
    var uasCount: Int?
    var rfidState: String?
    var heapFree: Int?
    var queueDrops: Int?

    enum CodingKeys: String, CodingKey {
        case uptimeSeconds = "uptime_s"
        case wifiCount = "wifi_count"
        case bleCount = "ble_count"
        case subghzCount = "subghz_count"
        case uasCount = "uas_count"
        case rfidState = "rfid_state"
        case heapFree = "heap_free"
        case queueDrops = "queue_drops"
    }
}

// MARK: - Action registry (§1.5 full control parity)

struct ARIAAction: Codable, Hashable, Identifiable {
    var name: String                 // raw command name, always renderable even if unmapped
    var label: String?
    var description: String?
    var command: String?             // endpoint/command to fire, e.g. "ui.rfid"
    var requiresConfirmation: Bool?
    var group: String?               // GROUP column (top-level mode)
    var page: String?                // PAGE column (sub-level)

    var id: String { command ?? name }

    enum CodingKeys: String, CodingKey {
        case name, label, description, command, group, page
        case requiresConfirmation = "requires_confirmation"
    }

    var displayLabel: String { label ?? name }
}

/// A top-level mode and the real action set discovered by walking into it.
struct ARIAMode: Identifiable, Hashable {
    var name: String
    var command: String?
    var actions: [ARIAAction]
    var id: String { command ?? name }
}

// MARK: - Session export (resilient, element-by-element parsing — §4)

struct ARIASessionExport {
    var summary: ARIASessionSummary?
    var wifi: [ARIAWiFiDevice]
    var ble: [ARIABLEDeviceRecord]
    var subghz: [ARIASubGHzCapture]
    var uas: [ARIAUASRecord]
    var rfid: [ARIARFIDTag]
    /// Count of records skipped during parsing (corruption / NUL-interleave). Surfaced in UI.
    var malformedSkipped: Int
    var raw: Data
    var warnings: [String] = []
    var modes: [ARIAMode] = []

    static let empty = ARIASessionExport(
        summary: nil, wifi: [], ble: [], subghz: [], uas: [], rfid: [],
        malformedSkipped: 0, raw: Data()
    )
}

/// Parses a full ARIA session export WITHOUT ever crashing or dropping the whole session
/// on a single bad record. Captures arrays are decoded element-by-element; failures are
/// counted and skipped, never repaired or guessed (spec §4).
enum ARIASessionParser {
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        return d
    }

    /// Decode one array of band records element-by-element.
    /// Returns (decoded, skippedCount). Never throws.
    static func decodeArray<T: Decodable>(
        _ raw: [Any]?,
        as type: T.Type
    ) -> ([T], Int) {
        guard let raw else { return ([], 0) }
        var out: [T] = []
        var skipped = 0
        let dec = decoder()
        for element in raw {
            // isValidJSONObject guard first: data(withJSONObject:) raises an uncatchable
            // ObjC exception on scalar garbage (NUL-interleaved shards), which do/catch can't
            // trap. Skip those up front so one bad record never crashes the session (§4).
            guard JSONSerialization.isValidJSONObject(element) else {
                skipped += 1
                continue
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: element, options: [])
                let value = try dec.decode(T.self, from: data)
                out.append(value)
            } catch {
                skipped += 1   // flag and continue; never repair sheared fields
            }
        }
        return (out, skipped)
    }

    /// Parse a full export blob. Top-level JSON that itself fails to parse yields an
    /// empty session with the whole payload marked malformed, rather than throwing.
    static func parse(_ data: Data) -> ARIASessionExport {
        guard
            let obj = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            ),
            let root = obj as? [String: Any]
        else {
            return ARIASessionExport(
                summary: nil, wifi: [], ble: [], subghz: [], uas: [], rfid: [],
                malformedSkipped: 1, raw: data
            )
        }

        var skipped = 0

        let summary: ARIASessionSummary? = {
            guard let s = root["summary"], JSONSerialization.isValidJSONObject(s) else { return nil }
            guard let d = try? JSONSerialization.data(withJSONObject: s) else { return nil }
            return try? decoder().decode(ARIASessionSummary.self, from: d)
        }()

        let (wifi, sW) = decodeArray(root["wifi"] as? [Any], as: ARIAWiFiDevice.self)
        let (ble, sB) = decodeArray(root["ble"] as? [Any], as: ARIABLEDeviceRecord.self)
        let (subghz, sS) = decodeArray(
            (root["subghz"] as? [Any]) ?? (root["captures"] as? [Any]),
            as: ARIASubGHzCapture.self
        )
        let (uas, sU) = decodeArray(root["uas"] as? [Any], as: ARIAUASRecord.self)
        let (rfid, sR) = decodeArray(root["rfid"] as? [Any], as: ARIARFIDTag.self)
        skipped += sW + sB + sS + sU + sR

        return ARIASessionExport(
            summary: summary,
            wifi: wifi, ble: ble, subghz: subghz, uas: uas, rfid: rfid,
            malformedSkipped: skipped,
            raw: data
        )
    }
}

/// Validates the wire format before any GPS annotation or typed record decoding.
/// Enabling fragments would accept null/strings but would not make HTML a session.
enum ARIAJSONResponse {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func object(_ data: Data, endpoint: String) throws -> [String: Any] {
        guard !data.isEmpty else { throw Failure(message: "\(endpoint): empty response; retry refresh") }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let prefix = String(decoding: data.prefix(120), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = prefix.hasPrefix("<") ? "HTML instead of JSON" : "invalid or incomplete JSON"
            throw Failure(message: "\(endpoint): \(kind); previous snapshot retained")
        }
        guard let root = value as? [String: Any] else {
            throw Failure(message: "\(endpoint): expected a JSON object, not a scalar or array")
        }
        if root["ok"] as? Bool == false || root["error"] != nil {
            let detail = root["error"] as? String ?? root["output"] as? String ?? "device reported an error"
            throw Failure(message: "\(endpoint): \(String(detail.prefix(180)))")
        }
        return root
    }

    /// Normalizes the documented live /api/devices schema and nested export schema.
    /// Retains the full source separately so normalization cannot erase evidence.
    static func session(_ source: [String: Any]) throws -> ARIASessionExport {
        let live = source["session"] as? [String: Any] ?? source
        guard live["devices"] is [Any] || source["wifi"] is [Any] else {
            throw Failure(message: "Session response has no recognized device arrays")
        }
        var root: [String: Any] = ["firmware_response": source]
        let devices = live["devices"] as? [[String: Any]] ?? []
        var wifi: [[String: Any]] = []
        var ble: [[String: Any]] = []
        for device in devices {
            let band = (device["band"] as? String ?? device["kind"] as? String ?? "").lowercased()
            var row = device
            if band == "ble" {
                row["address"] = device["mac"]
                row["name"] = device["name"] ?? device["ssid"]
                ble.append(row)
            } else if band == "wifi" {
                row["encryption"] = device["encrypt"]
                if let packets = device["pkts"] as? [String: Any] {
                    for key in ["probe", "beacon", "data", "deauth", "mgmt"] { row[key + "_count"] = packets[key] }
                }
                wifi.append(row)
            }
        }
        root["wifi"] = source["wifi"] as? [Any] ?? wifi
        root["ble"] = source["ble"] as? [Any] ?? ble
        let captures = source["captures"] as? [String: Any] ?? [:]
        let radio = source["subghz_live"] as? [String: Any] ?? [:]
        let raw = radio["packets"] as? [[String: Any]] ?? captures["subghz"] as? [[String: Any]] ?? source["subghz"] as? [[String: Any]] ?? []
        root["subghz"] = raw.map { packet -> [String: Any] in
            var row = packet
            row["boot"] = packet["boot_id"] ?? packet["boot"]
            row["frequency_mhz"] = packet["frequency_mhz"] ?? packet["mhz"]
            row["duration_us"] = packet["capture_duration_us"] ?? packet["duration_us"]
            if let rssi = packet["rssi"] as? NSNumber { row["rssi"] = rssi.intValue }
            if let observation = packet["observation"] as? [String: Any] {
                var decode: [String: Any] = [:]
                decode["decoded_status"] = observation["status"]
                decode["decoded_hex"] = observation["decoded_hex"]
                decode["verification_status"] = observation["status"]
                decode["raw_availability"] = packet["raw_availability"]
                if let fields = observation["fields"] as? [String: Any] {
                    decode["decoded_fields"] = fields.mapValues { String(describing: $0) }
                }
                row["decode"] = decode
            }
            return row
        }
        // Generic RF observations are deliberately not promoted to drone records.
        root["uas"] = source["uas"] as? [Any] ?? []
        let rfid = source["rfid"] as? [String: Any] ?? [:]
        root["rfid"] = source["rfid"] as? [Any] ?? rfid["observations"] as? [Any] ?? []
        var summary = source["summary"] as? [String: Any] ?? [:]
        if let uptime = live["uptime_ms"] as? Int { summary["uptime_s"] = uptime / 1000 }
        summary["wifi_count"] = (root["wifi"] as? [Any])?.count
        summary["ble_count"] = (root["ble"] as? [Any])?.count
        summary["subghz_count"] = (root["subghz"] as? [Any])?.count
        summary["rfid_state"] = rfid["state"]
        root["summary"] = summary
        var parsed = ARIASessionParser.parse(try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))
        parsed.warnings = source["poll_warnings"] as? [String] ?? []
        let tools = source["tools"] as? [String: Any] ?? [:]
        if let groups = tools["groups"] as? [[String: Any]] {
            parsed.modes = groups.compactMap { group in
                guard let name = group["name"] as? String else { return nil }
                let (actions, _) = ARIASessionParser.decodeArray(group["actions"] as? [Any], as: ARIAAction.self)
                return ARIAMode(name: name, command: nil, actions: actions)
            }
        }
        return parsed
    }
}
