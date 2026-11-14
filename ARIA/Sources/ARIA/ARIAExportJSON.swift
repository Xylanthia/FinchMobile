import Foundation

/// Export-only projection. Never feed this back into capture storage or UI decoding.
enum ARIAExportJSON {
    private static let bands: Set<String> = ["ble", "wifi", "subghz", "uas"]

    /// Remove absent object members, preserving false, zero, whitespace/payload strings,
    /// empty collections and array positions (which can be meaningful evidence).
    static func omitEmptyFields(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            return object.compactMapValues { value -> Any? in
                if value is NSNull || (value as? String) == "" { return nil }
                return omitEmptyFields(value)
            }
        }
        if let array = value as? [Any] { return array.map(omitEmptyFields) }
        return value
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let lhs, let rhs,
              let a = try? JSONSerialization.data(withJSONObject: lhs, options: [.sortedKeys, .fragmentsAllowed]),
              let b = try? JSONSerialization.data(withJSONObject: rhs, options: [.sortedKeys, .fragmentsAllowed]) else { return false }
        return a == b
    }

    /// Only known aliases are folded. Unrelated equal measurements are not duplicates.
    /// Conflicting nonempty source values stay visible instead of being silently discarded.
    private static func alias(_ object: inout [String: Any], _ canonical: String, _ aliases: [String]) {
        for key in aliases {
            guard let value = object[key] else { continue }
            if object[canonical] == nil { object[canonical] = value }
            if equal(object[canonical], value) { object.removeValue(forKey: key) }
        }
    }

    private static func band(of row: [String: Any]) -> String? {
        for key in ["band_kind", "band", "source", "radio", "kind"] {
            if let value = row[key] as? String, bands.contains(value) { return value }
        }
        if row["uas_id"] != nil { return "uas" }
        if row["radio_sequence"] != nil || row["observation"] != nil { return "subghz" }
        return nil
    }

    static func record(_ input: [String: Any], band: String) -> [String: Any] {
        var row = omitEmptyFields(input) as! [String: Any]
        row["band_kind"] = row["band_kind"] ?? band
        for key in ["band", "source", "radio"] where equal(row[key], row["band_kind"]) {
            row.removeValue(forKey: key)
        }
        if let kind = row["kind"] {
            if equal(kind, row["band_kind"]) { row.removeValue(forKey: "kind") }
            else { alias(&row, band == "wifi" ? "frame_type" : "device_type", ["kind"]) }
        }
        alias(&row, "boot_id", ["boot"])
        alias(&row, "frequency_mhz", ["mhz"])
        alias(&row, "duration_us", ["capture_duration_us"])
        switch band {
        case "ble":
            alias(&row, "address", ["mac"])
            alias(&row, "name", ["ssid"])
        case "wifi":
            alias(&row, "encryption", ["encrypt"])
            if var packets = row["pkts"] as? [String: Any] {
                for kind in ["probe", "beacon", "data", "deauth", "mgmt"] {
                    let key = kind + "_count"
                    if row[key] == nil { row[key] = packets[kind] }
                    if equal(row[key], packets[kind]) { packets.removeValue(forKey: kind) }
                }
                row["pkts"] = packets.isEmpty ? nil : packets
            }
        case "subghz":
            alias(&row, "length_bytes", ["len"])
            // These pairs are emitted by the same byte-formatting loops in firmware.
            // Keep distinct formats (spaced/contiguous hex, signed/unsigned, etc.).
            if equal(row["ascii"], row["utf8"]) { row.removeValue(forKey: "utf8") }
            alias(&row, "u8", ["dec"])
            subghzDecode(&row)
        case "uas":
            alias(&row, "latitude", ["lat"])
            alias(&row, "longitude", ["lon"])
            alias(&row, "altitude_geo_m", ["alt_geo", "altitude"])
            alias(&row, "horizontal_speed_mps", ["speed"])
            alias(&row, "height_m", ["height"])
            alias(&row, "heading_deg", ["heading"])
            alias(&row, "operator_id", ["op_id"])
            alias(&row, "operator_latitude", ["operator_lat", "op_lat"])
            alias(&row, "operator_longitude", ["operator_lon", "op_lon"])
            // The app aliases the transport into decoder_provenance; genuine decoder
            // provenance with a different value must remain separate.
            if equal(row["rid_transport"], row["decoder_provenance"]) { row.removeValue(forKey: "decoder_provenance") }
        default: break
        }
        return row
    }

    private static func subghzDecode(_ row: inout [String: Any]) {
        var observation = row["observation"] as? [String: Any] ?? [:]
        var decode = row["decode"] as? [String: Any] ?? [:]
        let observationStatus = observation["status"] ?? observation["decode_status"]
        let status = row["decode_status"] ?? row["decode_state"] ?? observationStatus ?? decode["decoded_status"] ?? decode["decode_status"]
        row["decode_status"] = status
        alias(&row, "decode_status", ["decode_state"])
        alias(&observation, "decode_status", ["status"])
        alias(&decode, "decode_status", ["decoded_status"])
        if equal(observation["decode_status"], status) { observation.removeValue(forKey: "decode_status") }
        if equal(decode["decode_status"], status) || equal(decode["decode_status"], observationStatus) {
            decode.removeValue(forKey: "decode_status")
        }
        // session() copies observation.status into verification_status; this is not an
        // independent verification. Preserve verification from other record shapes.
        if equal(decode["verification_status"], observationStatus) { decode.removeValue(forKey: "verification_status") }
        if equal(decode["decoded_hex"], observation["decoded_hex"]) { decode.removeValue(forKey: "decoded_hex") }
        if equal(decode["raw_availability"], row["raw_availability"]) { decode.removeValue(forKey: "raw_availability") }
        if equal(decode["decoded_fields"], observation["fields"]) { decode.removeValue(forKey: "decoded_fields") }
        row["observation"] = observation.isEmpty ? nil : observation
        row["decode"] = decode.isEmpty ? nil : decode
    }

    /// Visit only known envelope/record locations. Decoder fields and arbitrary metadata
    /// may legitimately use keys such as kind, status, band or duration_us.
    static func document(_ input: [String: Any], recordBand: String? = nil) -> [String: Any] {
        var root = omitEmptyFields(input) as! [String: Any]
        for (key, value) in root {
            if let array = value as? [Any], bands.contains(key) || ["devices", "detections", "packets", "observations"].contains(key) {
                root[key] = array.map { value -> Any in
                    guard let row = value as? [String: Any],
                          let source = bands.contains(key) ? key : band(of: row) ?? recordBand else { return value }
                    if let stored = row["record"] as? [String: Any] {
                        var wrapper = row
                        wrapper["record"] = record(stored, band: source)
                        return wrapper
                    }
                    return record(row, band: source)
                }
            } else if let object = value as? [String: Any],
                      ["firmware_response", "session", "capabilities", "captures", "subghz_live", "uas", "live_snapshot_at_export"].contains(key) {
                root[key] = document(object, recordBand: key == "subghz_live" ? "subghz" : key == "uas" ? "uas" : nil)
            }
        }
        return root
    }

    static func data(_ input: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: input)
        guard let root = object as? [String: Any] else {
            throw NSError(domain: "ARIAExportJSON", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export must contain a JSON object."])
        }
        return try JSONSerialization.data(withJSONObject: document(root), options: [.prettyPrinted, .sortedKeys])
    }

    static func recordJSON(_ input: String, band: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(input.utf8))
        guard let row = object as? [String: Any] else {
            throw NSError(domain: "ARIAExportJSON", code: 2, userInfo: [NSLocalizedDescriptionKey: "Export record must contain a JSON object."])
        }
        let data = try JSONSerialization.data(withJSONObject: record(row, band: band), options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
