import Foundation

@main struct OverviewTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let devices: [[String: Any]] = [
            ["mac": "AA:01", "band": "wifi", "category": "computer", "last_seen_ms": 60001],
            ["mac": "AA:02", "band": "ble", "category": "phone", "last_seen_ms": 1000],
            ["mac": "AA:03", "band": "ble", "vendor": "Apple", "last_seen_ms": 0],
            ["mac": "AA:04", "band": "wifi", "vendor": "Samsung", "category": "unclassified"],
            ["mac": "AA:05", "band": "wifi", "category": "drone_control_candidate"],
            ["mac": "AA:06", "band": "wifi", "category": "drone", "last_seen_ms": 0]
        ]
        let captures: [[String: Any]] = [
            ["sequence": 1, "boot": 10, "ts_ms": 99000, "decode": ["decoded_status": "VERIFIED"]],
            ["sequence": 2, "boot": 10, "ts_ms": 99000, "decode": ["decoded_status": "UNKNOWN"]],
            ["sequence": 3, "boot": 10, "ts_ms": 99000, "decode": ["decoded_status": "INCOMPLETE"]],
            ["sequence": 4, "boot": 10, "decode": ["decoded_status": "ERROR"]],
            ["sequence": 5, "boot": 10]
        ]
        let session = try ARIAJSONResponse.session([
            "session": ["uptime_ms": 100000, "devices": devices], "subghz": captures
        ])
        precondition(session.wifi.first?.category == "computer", "Wi-Fi firmware category survives parsing")
        precondition(session.ble.first?.category == "phone", "BLE firmware category survives parsing")
        precondition(session.ble.count == 2 && session.wifi.count == 4, "Unclassified records remain in radio arrays")
        let normalized = ARIAJSONResponse.normalizeDevice(["address": "AA:02", "band": "ble", "category": "phone"])!
        precondition(normalized.row["address"] as? String == "AA:02", "History BLE address survives normalization")
        let encoded = try JSONEncoder().encode(session.ble.first!)
        let restoredBLE = try JSONDecoder().decode(ARIABLEDeviceRecord.self, from: encoded)
        precondition(restoredBLE.category == "phone")
        var catalog = ARIAOverviewCatalog()
        catalog.ingestSession(session.raw, now: now)
        var rows = catalog.rows(now: now, connected: true)
        precondition(rows.first { $0.id == "computer" }?.live == 0)
        precondition(rows.first { $0.id == "computer" }?.total == 1)
        precondition(rows.first { $0.id == "phone" }?.live == 1)
        precondition(rows.first { $0.id == "subghz_decoded" }?.total == 1)
        precondition(rows.first { $0.id == "subghz_decoded" }?.live == 1, "Sub-GHz firmware ts_ms uses uptime")
        precondition(!rows.contains { ["unclassified", "drone_control_candidate"].contains($0.id) })
        let capabilities: [String: Any] = [
            "uptime_ms": 100000,
            "detections": [
                ["category": "alpr_camera", "mac": "BB:01", "radio": "ble", "last_seen_ms": 99000, "matched_patterns": ["name:flock"]],
                ["category": "gunshot_detector", "mac": "BB:02", "radio": "wifi", "last_seen_ms": 1],
                ["category": "drone", "mac": "aa:06", "radio": "wifi", "last_seen_ms": 100000],
                ["category": "drone_control_candidate", "mac": "BB:03", "radio": "wifi"]
            ],
            "uas": ["observations": [
                ["uas_id": "RID1", "validation": true, "classification": "VALIDATED_REMOTE_ID", "last_seen_ms": 99900, "id_type": 1],
                ["uas_id": "RID1", "validation": true, "classification": "VALIDATED_REMOTE_ID", "last_seen_ms": 99900],
                ["uas_id": "bad", "validation": false, "classification": "UNKNOWN_RF"],
                ["uas_id": " ", "validation": true, "classification": "VALIDATED_REMOTE_ID"]
            ]]
        ]
        // Real firmware transport shape: four classes in the SAME poll, including
        // numeric RID types and raw Sub-GHz observation status (not app-only fixtures).
        var firmwareCapabilities = capabilities
        firmwareCapabilities["uas"] = ["observations": [
            ["uas_id": "RID-LIVE", "validation": true, "classification": "VALIDATED_REMOTE_ID",
             "id_type": 1, "ua_type": 2, "lat": 42.0, "lon": -83.0, "alt_geo": 120.5,
             "speed": 4.5, "op_id": "operator", "op_lat": 42.1, "op_lon": -83.1,
             "rid_transport": "BLE service data", "last_seen_ms": 99900, "raw_evidence_id": 81],
            ["uas_id": "RF-NOISE", "validation": false, "classification": "UNKNOWN_RF"],
            ["uas_id": "UNVALIDATED", "validation": false, "classification": "VALIDATED_REMOTE_ID"],
            ["uas_id": "\n ", "validation": true, "classification": "VALIDATED_REMOTE_ID"]
        ]]
        let liveSource: [String: Any] = [
            "session": ["uptime_ms": 100000, "devices": devices],
            "capabilities": firmwareCapabilities,
            "subghz_live": ["packets": [
                ["sequence": 21, "boot_id": 5, "ts_ms": 99000, "observation": ["status": "VERIFIED", "decoded_hex": "1234"]],
                ["sequence": 22, "boot_id": 5, "observation": ["status": "UNKNOWN"]],
                ["sequence": 23, "boot_id": 5, "observation": ["status": "INCOMPLETE"]],
                ["sequence": 24, "boot_id": 5, "observation": ["status": "CANDIDATE"]]
            ]]
        ]
        let liveSession = try ARIAJSONResponse.session(liveSource)
        precondition(liveSession.malformedSkipped == 0)
        precondition(liveSession.uas.count == 1, "Validated firmware RID reaches the UAS tab/history")
        let aircraft = liveSession.uas[0]
        precondition(aircraft.uasID == "RID-LIVE" && aircraft.idType == "1" && aircraft.uaType == "2")
        precondition(aircraft.latitude == 42 && aircraft.longitude == -83 && aircraft.altitude == 120.5)
        precondition(aircraft.speed == 4.5 && aircraft.operatorID == "operator")
        precondition(aircraft.operatorLatitude == 42.1 && aircraft.operatorLongitude == -83.1)
        precondition(aircraft.decoderProvenance == "BLE service data")
        precondition(liveSession.subghz.count == 4, "Unknown/partial/candidate captures remain on their radio tab")
        let normalizedLive = try JSONSerialization.jsonObject(with: liveSession.raw) as! [String: Any]
        let rawFirmware = normalizedLive["firmware_response"] as! [String: Any]
        precondition(NSDictionary(dictionary: rawFirmware).isEqual(to: liveSource), "Original evidence survives normalization")
        var integrated = ARIAOverviewCatalog()
        integrated.ingestSession(liveSession.raw, now: now)
        integrated.ingestCapabilities(rawFirmware["capabilities"] as! [String: Any], now: now)
        let integratedRows = integrated.rows(now: now, connected: true)
        for category in ["phone", "computer", "drone", "subghz_decoded"] {
            precondition(integratedRows.contains { $0.id == category && $0.total > 0 })
        }
        precondition(integratedRows.first { $0.id == "subghz_decoded" }?.total == 1)
        let exported = try ARIAJSONResponse.session(["wifi": [], "uas": firmwareCapabilities["uas"]!])
        precondition(exported.uas == liveSession.uas, "Nested capture exports use the same RID adapter")
        let legacy = try ARIAJSONResponse.session(["wifi": [], "uas": [["uas_id": "legacy", "id_type": "serial"]]])
        precondition(legacy.uas.first?.idType == "serial")
        catalog.ingestCapabilities(capabilities, now: now)
        catalog.ingestCapabilities(capabilities, now: now)
        rows = catalog.rows(now: now, connected: true)
        precondition(rows.prefix(3).map(\.id) == ["alpr_camera", "gunshot_detector", "drone"])
        precondition(rows.first { $0.id == "drone" }?.total == 2, "One unique RID plus one fingerprint; detection roster duplicate excluded")
        precondition(rows.first { $0.id == "gunshot_detector" }?.live == 0, "Detection time is uptime, not age")
        precondition(rows.first { $0.id == "alpr_camera" }?.records.first?.fields["matched_patterns"] as? [String] == ["name:flock"])
        precondition(rows.allSatisfy { $0.total > 0 && $0.live <= $0.total })
        precondition(catalog.rows(now: now.addingTimeInterval(61), connected: true).allSatisfy { $0.live == 0 })
        precondition(catalog.rows(now: now, connected: false).allSatisfy { $0.live == 0 && $0.total > 0 })
        // Empty follow-up snapshots and app relaunch retain totals and original sighting time.
        catalog.ingestCapabilities(["uptime_ms": 200000, "detections": []], now: now.addingTimeInterval(100))
        let saved = try JSONEncoder().encode(catalog)
        let restored = try JSONDecoder().decode(ARIAOverviewCatalog.self, from: saved)
        precondition(restored.records.count == catalog.records.count)
        precondition(restored.rows(now: now.addingTimeInterval(100), connected: true).allSatisfy { $0.live == 0 })
        precondition(ARIAOverviewCatalog().rows(now: now, connected: true).isEmpty)
        var manyBLE = ARIAOverviewCatalog()
        let classifiedBLE = (0..<101).map { ["address": "BLE-\($0)", "category": "phone", "last_seen_ms": 0] as [String: Any] }
        let manyData = try JSONSerialization.data(withJSONObject: ["ble": classifiedBLE])
        manyBLE.ingestSession(manyData, now: now)
        precondition(manyBLE.rows(now: now, connected: true).first?.total == 101)
        precondition(manyBLE.rows(now: now.addingTimeInterval(60), connected: true).first?.live == 101)
        precondition(manyBLE.rows(now: now.addingTimeInterval(60.001), connected: true).first?.live == 0)
        precondition(manyBLE.rows(now: now.addingTimeInterval(-1), connected: true).first?.live == 0)
        // An aged response cannot restart the live window just because it was polled again.
        let aged = try JSONSerialization.data(withJSONObject: ["ble": [["address": "BLE-0", "category": "phone", "last_seen_ms": 70000]]])
        manyBLE.ingestSession(aged, now: now.addingTimeInterval(70))
        precondition(manyBLE.rows(now: now.addingTimeInterval(70), connected: true).first?.live == 0)
        print("PASS: category parsing, BLE history, vendor-only exclusion, age/uptime, decoded captures, RID/detection deduplication, priority, filtering, persistence and expiry")
    }
}
