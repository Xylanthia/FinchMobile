import Foundation

enum ARIAClient {
    struct Failure: LocalizedError {
        var message: String
        var statusCode: Int?
        var errorDescription: String? { message }
    }
}

@main struct ExportJSONTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func same(_ a: Any, _ b: Any) -> Bool {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed]
        return try! JSONSerialization.data(withJSONObject: a, options: options) == JSONSerialization.data(withJSONObject: b, options: options)
    }

    static func noEmptyMembers(_ value: Any) {
        if let object = value as? [String: Any] {
            for (key, member) in object {
                check(!(member is NSNull) && (member as? String) != "", "empty member: \(key)")
                noEmptyMembers(member)
            }
        } else if let array = value as? [Any] { array.forEach(noEmptyMembers) }
    }

    static func main() async throws {
        let representations = ["ascii", "base64", "bits", "bits_contig", "dec", "hex", "hex_contig", "nibbles", "oct", "s8", "s16_be", "s16_le", "s32_be", "s32_le", "u8", "u16_be", "u16_le", "u32_be", "u32_le", "utf8", "future_representation"]
        var subghz: [String: Any] = Dictionary(uniqueKeysWithValues: representations.map { ($0, "" as Any) })
        subghz.merge([
            "sequence": 4, "boot": 7, "boot_id": 7, "mhz": 433.92, "frequency_mhz": 433.92,
            "capture_duration_us": 2000, "duration_us": 2000, "decode_state": "INCOMPLETE",
            "raw_availability": "PRESENT", "rssi": -68.5, "pulses": [1, 32769], "replay_eligible": false,
            "observation": ["status": "INCOMPLETE", "decoded_hex": "", "protocol_validated": false, "fields": [:]],
            "decode": ["decoded_status": "INCOMPLETE", "verification_status": "INCOMPLETE", "decoded_hex": "", "raw_availability": "PRESENT"],
        ]) { _, new in new }
        let wifi: [String: Any] = ["mac": "AA:01", "band": "wifi", "kind": "beacon", "encrypt": "WPA2", "encryption": "WPA2", "ssid": NSNull(), "lat": NSNull(), "zone": "", "pkts": ["probe": 0, "beacon": 3], "probe_count": 0, "beacon_count": 3]
        let ble: [String: Any] = ["mac": "BB:01", "address": "BB:01", "band": "ble", "kind": "ble", "ssid": "Sensor", "name": "Sensor", "lat": NSNull(), "lon": NSNull()]
        let uas: [String: Any] = ["uas_id": "RID-1", "validation": true, "classification": "VALIDATED_REMOTE_ID", "lat": 0, "latitude": 0, "lon": -71.2, "longitude": -71.2, "alt_geo": 12.5, "altitude": 12.5, "altitude_geo_m": 12.5, "altitude_baro_m": 12.5, "height": 0, "height_m": 0, "speed": 0, "horizontal_speed_mps": 0, "heading": 90, "heading_deg": 90, "op_lat": 40.5, "operator_lat": 40.5, "operator_latitude": 40.5, "op_lon": -70.5, "operator_longitude": -70.5, "op_id": "op", "operator_id": "op", "rid_transport": "BLE", "decoder_provenance": "BLE"]
        let records = ["wifi": wifi, "ble": ble, "subghz": subghz, "uas": uas]
        let source: [String: Any] = records.mapValues { [$0] }
        let original = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys])
        let exportedData = try ARIAExportJSON.data(original)
        let exported = try JSONSerialization.jsonObject(with: exportedData) as! [String: Any]
        noEmptyMembers(exported)
        let originalObject = try JSONSerialization.jsonObject(with: original)
        check(same(source, originalObject), "source data is immutable")
        check(same(exported, ARIAExportJSON.document(exported)), "export projection is idempotent")
        func first(_ source: String) -> [String: Any] { (exported[source] as! [[String: Any]])[0] }
        let sg = first("subghz")
        for key in representations { check(sg[key] == nil, "empty representation omitted: \(key)") }
        check(sg["decode_status"] as? String == "INCOMPLETE" && sg["decode_state"] == nil && sg["decode"] == nil, "one decode status")
        check((sg["observation"] as! [String: Any])["status"] == nil, "remove duplicate observation status")
        check(sg["boot_id"] as? Int == 7 && sg["boot"] == nil && sg["mhz"] == nil && sg["capture_duration_us"] == nil, "canonical capture aliases")
        check(sg["rssi"] as? Double == -68.5 && sg["replay_eligible"] as? Bool == false && same(sg["pulses"]!, [1, 32769]), "measurements, false and waveform preserved")
        check(first("wifi")["frame_type"] as? String == "beacon" && first("wifi")["encrypt"] == nil && first("wifi")["pkts"] == nil && first("wifi")["probe_count"] as? Int == 0, "WiFi kind/encryption/counts")
        check(first("ble")["name"] as? String == "Sensor" && first("ble")["ssid"] == nil && first("ble")["mac"] == nil && first("ble")["kind"] == nil && first("ble")["frame_type"] == nil, "BLE kind/name/address")
        let aircraft = first("uas")
        for key in ["lat", "lon", "alt_geo", "altitude", "speed", "height", "heading", "op_lat", "operator_lat", "op_lon", "op_id", "decoder_provenance"] { check(aircraft[key] == nil, "UAS alias: \(key)") }
        check(aircraft["latitude"] as? Int == 0 && aircraft["altitude_baro_m"] as? Double == 12.5, "zero coordinate and distinct equal barometric altitude retained")
        for source in records.keys { check(first(source)["band_kind"] as? String == source && first(source)["kind"] == nil, "band_kind: \(source)") }

        // Decode readiness can differ from the decoder result. Verification/checksums and
        // statuses inside opaque protocol fields must not be deduplicated by coincidence.
        var pending = subghz
        pending["decode_state"] = "PENDING"
        pending["observation"] = ["status": "INCOMPLETE", "fields": ["kind": "sensor", "status": "INCOMPLETE", "mhz": 123]]
        let p = ARIAExportJSON.record(pending, band: "subghz")
        check(p["decode_status"] as? String == "PENDING", "capture readiness remains authoritative")
        let observation = p["observation"] as! [String: Any]
        check(observation["decode_status"] as? String == "INCOMPLETE" && observation["status"] == nil, "differing observation decode result is scoped")
        check(p["decode"] == nil, "copied pending result does not appear twice")
        check(same(observation["fields"]!, ["kind": "sensor", "status": "INCOMPLETE", "mhz": 123]), "opaque protocol fields untouched")
        let verified = ARIAExportJSON.record(["decode": ["decoded_status": "DECODED", "verification_status": "CRC_PASS"], "checksum_status": "CRC_PASS"], band: "subghz")
        check((verified["decode"] as! [String: Any])["verification_status"] as? String == "CRC_PASS" && verified["checksum_status"] as? String == "CRC_PASS", "independent verification retained")
        let conflict = ARIAExportJSON.record(["mhz": 433.9, "frequency_mhz": 433.92, "boot": 1, "boot_id": 2, "radio_boot_id": 2, "len": 0, "length_bytes": false], band: "subghz")
        check(conflict["mhz"] as? Double == 433.9 && conflict["boot"] as? Int == 1 && conflict["radio_boot_id"] as? Int == 2 && conflict["len"] as? Int == 0, "conflicts, radio boot and false versus zero are not aliases")
        let content = Dictionary(uniqueKeysWithValues: representations.map { ($0, "payload-" + $0 as Any) })
        let kept = ARIAExportJSON.record(content, band: "subghz")
        for key in representations { check(same(kept[key]!, content[key]!), "nonempty representation: \(key)") }
        let duplicateText = ARIAExportJSON.record(["ascii": "ABC", "utf8": "ABC", "dec": "65 66 67", "u8": "65 66 67"], band: "subghz")
        check(duplicateText["ascii"] as? String == "ABC" && duplicateText["utf8"] == nil && duplicateText["dec"] == nil && duplicateText["u8"] as? String == "65 66 67", "proven equivalent byte formats collapse")

        let nested: [String: Any] = ["firmware_response": ["session": ["devices": [wifi, ble]], "subghz_live": ["packets": [subghz]], "capabilities": ["uas": ["observations": [uas]]]], "live_snapshot_at_export": source]
        let cleaned = ARIAExportJSON.document(nested)
        let firmware = cleaned["firmware_response"] as! [String: Any]
        let packets = (firmware["subghz_live"] as! [String: Any])["packets"] as! [[String: Any]]
        check(same(packets[0], sg), "nested original firmware snapshots cleaned too")
        check(same(cleaned["live_snapshot_at_export"]!, exported), "history embedded live export uses same schema")

        // Actual streaming writer: includes all bands, all stored observations, headers,
        // counts and unchanged stored JSON. No decoder or capture logic is involved.
        let db = ARIAHistoryDB()
        check(db.openError == nil, "store opens")
        db.clear()
        defer { db.clear() }
        let rows = ARIALogSource.allCases.map { source -> ARIAHistoryRow in
            var row = records[source.rawValue]!
            row["capture_id"] = source.rawValue + "-capture"
            row["source"] = source.rawValue
            return ARIAHistoryCodec.row(source, row, fromLog: true)!
        }
        check(db.upsert(rows, at: Date(timeIntervalSince1970: 1000), cursor: nil), "fixture stored")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aria-export-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let header: [String: Any] = ["schema": "export-test", "absent": NSNull(), "empty": "", "live_snapshot_at_export": source]
        let summary: ([ARIALogSource: Int]) -> [String: Any] = { counts in ["counts": Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }), "unknown": NSNull()] }
        #if FINCH_EXPORT_TEST
        let counts = try db.writeExport(to: url, header: header, liveKeys: [], summary: summary)
        #else
        let counts = try db.writeExport(to: url, header: header, summary: summary)
        #endif
        let history = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        noEmptyMembers(history)
        check(history["schema"] as? String == "export-test", "scalar header is not null")
        for row in rows {
            let array = history[row.source.rawValue] as! [[String: Any]]
            check(array.count == counts[row.source] && array.count == 1, "streamed count matches array")
            let stored = try JSONSerialization.jsonObject(with: Data(row.json.utf8)) as! [String: Any]
            check(same(array[0]["record"]!, ARIAExportJSON.record(stored, band: row.source.rawValue)), "history/live schema parity")
            check(db.json(row.source, row.key) == row.json, "stored evidence unchanged")
        }
        #if !FINCH_EXPORT_TEST
        let events = history["observations"] as! [[String: Any]]
        check(events.count == 4 && history["observation_count"] as? Int == 4, "observation counts unchanged")
        for event in events { check(event["band_kind"] != nil && event["source"] == nil, "observation schema parity") }
        #endif
        do {
            _ = try ARIAExportJSON.recordJSON("invalid JSON", band: "ble")
            preconditionFailure("invalid stored JSON must not become null")
        } catch { }
        print("PASS: export schema across all four bands, live/nested/history parity, empty omission, aliases, status semantics, value preservation and unchanged storage")
    }
}
