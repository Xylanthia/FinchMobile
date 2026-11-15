import Foundation

/// Export-only projection. Never feed this back into capture storage or UI decoding.
enum ARIAExportJSON {
    private static let bands: Set<String> = ["ble", "wifi", "subghz", "lora", "uas"]

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
                    // Dashboard device rows already contain the normalized canonical
                    // record under `raw`; applying per-band aliases to the projection
                    // would remove dashboard fields such as BLE `mac` on a second pass.
                    if key == "devices", row["observation_status"] != nil, row["raw"] != nil { return value }
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

    /// Dashboard v4 device projection. The original source records remain available in the
    /// per-band arrays and `raw`; this adds the same stable device rows and summary envelope
    /// consumed by the web dashboard.
    static func dashboardDevice(_ input: [String: Any], band: String, live: Bool, ageMS: Int?) -> [String: Any] {
        let source = omitEmptyFields(input) as? [String: Any] ?? input
        var row = record(source, band: band)
        let rssi = (source["rssi"] as? NSNumber)?.doubleValue
        let distance = rssi.map { pow(10, (-40 - $0) / 25) }
        let lat = source["latitude"] ?? source["lat"]
        let lon = source["longitude"] ?? source["lon"]
        let gps = source["gps"] as? Bool == true && lat != nil && lon != nil
        row["raw"] = source
        row["observation_status"] = live ? "live" : "previously_seen"
        row["live"] = live
        row["age_ms"] = ageMS.map { $0 as Any } ?? NSNull()
        row["trust"] = source["trust"] ?? "none"
        row["avg"] = source["avg"] ?? source["rssi"] ?? NSNull()
        row["channel"] = source["channel"] ?? source["ch"] ?? NSNull()
        row["band"] = band
        // Dashboard v4 uses `mac` as the common device-list address key. Preserve the
        // canonical BLE `address` field as well in the per-band record; this projection
        // supplies the dashboard field without changing the source evidence.
        if let address = source["mac"] ?? source["address"] { row["mac"] = address }
        row["kind"] = source["kind"] ?? ""
        row["ssid"] = band == "ble" ? NSNull() : (source["ssid"] ?? NSNull())
        row["bssid"] = source["bssid"] ?? NSNull()
        row["name"] = source["name"] ?? source["ssid"] ?? ""
        row["vendor"] = source["vendor"] ?? ""
        row["encryption"] = source["encryption"] ?? source["encrypt"] ?? ""
        row["rand_mac"] = (source["rand"] as? Bool) ?? false
        row["distance_m"] = distance.map { $0 as Any } ?? NSNull()
        row["zone"] = distance.map { $0 <= 5 ? "Near" : $0 <= 20 ? "Mid" : "Far" as Any } ?? NSNull()
        row["gps_lat"] = gps ? lat! : NSNull() as Any
        row["gps_lon"] = gps ? lon! : NSNull() as Any
        row["location_scope"] = gps ? "receiver" : "unknown"
        row["device_location"] = NSNull()
        row["proximity_method"] = distance == nil ? NSNull() as Any : "rssi_path_loss_estimate"
        row["verification_status"] = source["verification_status"] ?? "OBSERVED"
        row["host_received_at"] = source["host_received_at"] ?? NSNull()
        row["timestamp_method"] = source["timestamp_method"] ?? "handheld_observation"
        row["acquisition_timestamp"] = source["acquisition_timestamp"] ?? NSNull()
        row["receiver_monotonic_ms"] = source["timestamp_ms"] ?? NSNull()
        row["gps_confidence"] = source["gps_confidence"] ?? NSNull()
        row["pkt_count"] = source["seen_count"] ?? 0
        row["pkt_rate"] = source["pkt_rate"] ?? 0
        let packets = source["pkts"] as? [String: Any] ?? [:]
        for key in ["probe", "beacon", "data", "deauth", "mgmt"] {
            row["pkt_\(key)"] = source["\(key)_count"] ?? packets[key] ?? 0
        }
        row["first_seen"] = source["first_seen"] ?? NSNull()
        row["last_seen"] = source["last_seen"] ?? NSNull()
        row["signal_class"] = source["signal_class"] ?? NSNull()
        row["frequency_mhz"] = source["frequency_mhz"] ?? source["mhz"] ?? NSNull()
        row["sightings"] = source["sightings"] ?? []
        row["observation_history"] = source["observation_history"] ?? []
        row["observation_history_omitted"] = source["observation_history_omitted"] ?? 0
        return row
    }

    static func dashboardDocument(_ input: [String: Any]) -> [String: Any] {
        var root = document(input)
        let firmware = root["firmware_response"] as? [String: Any] ?? [:]
        let session = firmware["session"] as? [String: Any] ?? firmware
        let capabilities = firmware["capabilities"] as? [String: Any] ?? [:]
        let uptime = (session["uptime_ms"] as? NSNumber)?.doubleValue
            ?? (capabilities["uptime_ms"] as? NSNumber)?.doubleValue

        func ageMilliseconds(_ row: [String: Any], band: String) -> Int? {
            if let age = (row["age_ms"] as? NSNumber)?.intValue { return max(0, age) }
            guard let last = (row["last_seen_ms"] as? NSNumber)?.intValue else { return nil }
            // Remote ID timestamps are absolute handheld uptime values. Device-list
            // last_seen_ms values are ages, so only Remote ID needs the uptime anchor.
            if band == "uas" {
                guard let uptime, uptime >= Double(last) else { return nil }
                return Int(uptime - Double(last))
            }
            return max(0, last)
        }

        func project(_ row: [String: Any], band: String) -> [String: Any] {
            let age = ageMilliseconds(row, band: band)
            let live = (row["live"] as? Bool) ?? (age.map { $0 < 60_000 } ?? false)
            return dashboardDevice(row, band: band, live: live, ageMS: age)
        }

        let sourceRows: [(String, [[String: Any]])] = bands.sorted().map { band in
            let rows = root[band] as? [[String: Any]] ?? []
            return (band, rows)
        }
        var devices = root["devices"] as? [[String: Any]] ?? []
        if devices.isEmpty {
            for (band, rows) in sourceRows {
                devices.append(contentsOf: rows.map { row in
                    project(row, band: band)
                })
            }
        } else {
            devices = devices.map { row in
                let band = band(of: row) ?? "wifi"
                return project(row, band: band)
            }
        }
        let oldSchema = root["schema"]
        root["schema_version"] = 4
        if let oldSchema { root["source_schema"] = oldSchema; root.removeValue(forKey: "schema") }
        root["exported_at"] = root["exported_at"] ?? ISO8601DateFormatter().string(from: Date())
        root["history_scope"] = root["history_scope"] ?? "Observations retained by the ARIA mobile session store"
        root["live_definition"] = root["live_definition"] ?? ["max_age_ms": 60_000, "meaning": "Last heard within 60 seconds; session rows remain exported after they leave range"]
        root["name"] = root["name"] ?? "ARIA"
        root["paused"] = root["paused"] ?? false
        root["whitelist"] = root["whitelist"] ?? []
        root["blacklist"] = root["blacklist"] ?? []
        root["scanner_gps"] = root["scanner_gps"] ?? NSNull()
        root["rf_status"] = root["rf_status"] ?? NSNull()
        root["last_successful_poll_at"] = root["last_successful_poll_at"] ?? NSNull()
        root["snapshot_age_ms"] = root["snapshot_age_ms"] ?? NSNull()
        root["latest_api_snapshot"] = root["latest_api_snapshot"] ?? root["firmware_response"] ?? NSNull()
        root["path_loss"] = root["path_loss"] ?? ["n": 2.5, "ref_rssi_1m": -40, "zone_near_m": 5, "zone_mid_m": 20, "description": "RSSI-derived estimates only; not measured positions"]
        root["count"] = devices.count
        root["count_live"] = devices.filter { $0["live"] as? Bool == true }.count
        root["count_previously_seen"] = devices.count - (root["count_live"] as? Int ?? 0)
        root["count_wifi_ble"] = devices.filter { !["subghz", "lora"].contains($0["band"] as? String ?? "") }.count
        root["count_subghz"] = devices.filter { $0["band"] as? String == "subghz" }.count
        root["count_lora"] = devices.filter { $0["band"] as? String == "lora" }.count
        let bodyCamMatches: [[String: Any]] = devices.compactMap { row in
            let band = row["band"] as? String ?? ""
            let match: ARIABodyCam.Match?
            if band == "ble" {
                match = ARIABodyCam.match(mac: row["address"] as? String ?? row["mac"] as? String,
                                          companyID: row["company_id"] as? String,
                                          advHex: (row["decode"] as? [String: Any])?["raw_hex"] as? String)
            } else if band == "wifi" {
                match = ARIABodyCam.matchMAC(row["mac"] as? String) ?? ARIABodyCam.matchMAC(row["bssid"] as? String)
            } else { match = nil }
            guard let match else { return nil }
            return ["maker": match.maker, "evidence": match.evidence,
                    "device_id": row["device_id"] ?? row["mac"] ?? row["address"] ?? NSNull(),
                    "band": band, "live": row["live"] ?? false]
        }
        root["body_cam_coverage"] = [
            "scope": "BLE/Wi-Fi identifiers in retained ARIA session records",
            "matches_are_candidates": true,
            "matches": bodyCamMatches,
            "candidate_count": bodyCamMatches.count,
            "live_candidate_count": bodyCamMatches.filter { $0["live"] as? Bool == true }.count,
            "session_candidate_count": bodyCamMatches.count,
            "registry_makers": ["Axon", "WatchGuard Video", "Digital Ally", "Utility (BodyWorn)"],
        ] as [String: Any]
        root["devices"] = devices
        return omitEmptyFields(root) as! [String: Any]
    }

    static func data(_ input: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: input)
        guard let root = object as? [String: Any] else {
            throw NSError(domain: "ARIAExportJSON", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export must contain a JSON object."])
        }
        return try JSONSerialization.data(withJSONObject: dashboardDocument(root), options: [.prettyPrinted, .sortedKeys])
    }

    /// Adds the dashboard v4 device list to the boot-to-export history document. The
    /// per-band log records and every observation remain available alongside the list.
    static func historyDocument(_ input: Data, liveKeys: Set<String>) throws -> Data {
        guard var root = (try JSONSerialization.jsonObject(with: input)) as? [String: Any] else {
            throw NSError(domain: "ARIAExportJSON", code: 2, userInfo: [NSLocalizedDescriptionKey: "Session history must contain a JSON object."])
        }
        root = document(root)
        var devices: [[String: Any]] = []
        for band in bands.sorted() {
            for wrapper in root[band] as? [[String: Any]] ?? [] {
                guard var record = wrapper["record"] as? [String: Any] else { continue }
                record["live"] = liveKeys.contains("\(band):\(wrapper["key"] as? String ?? "")")
                devices.append(record)
            }
        }
        root["devices"] = devices
        root["schema_version"] = 4
        root["history_scope"] = "All available observations from the current ARIA handheld boot through export"
        return try JSONSerialization.data(withJSONObject: dashboardDocument(root), options: [.prettyPrinted, .sortedKeys])
    }

    static func rewriteHistoryExport(at url: URL, liveKeys: Set<String>) throws {
        do {
            let input = try Data(contentsOf: url)
            let output = try historyDocument(input, liveKeys: liveKeys)
            try output.write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
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
