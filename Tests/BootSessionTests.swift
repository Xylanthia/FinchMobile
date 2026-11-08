import Foundation

// The store only depends on the client's error type; these tests perform no networking.
enum ARIAClient {
    struct Failure: LocalizedError {
        var message: String
        var statusCode: Int?
        var errorDescription: String? { message }
    }
}

@main struct BootSessionTests {
    @MainActor static func main() async throws {
        let history = ARIAHistory()
        precondition(history.wifi.isEmpty && history.bootID == nil)
        await history.beginSession(boot: 42)
        let stats: [String: Any] = ["epoch": "abc", "last_seq": 102, "this_boot": 3, "pending_unflushed": 1]
        precondition(ARIAHistory.bootFloor(stats) == 100)
        history.seedCursor(.wifi, stats: stats)
        func record(_ seq: Int, boot: Int = 42) -> [String: Any] {
            ["seq": seq, "boot": boot, "capture_id": "wifi-abc-\(seq)", "mac": "AA:01", "band": "wifi", "category": "computer"]
        }
        let old = await history.ingestLog(.wifi, epoch: "abc", records: [record(100, boot: 41)], requireContiguous: true)
        precondition(old && history.wifi.isEmpty)
        let gap = await history.ingestLog(.wifi, epoch: "abc", records: [record(101), record(103)], requireContiguous: true)
        precondition(!gap && history.wifi.isEmpty, "Interior gaps cannot silently advance export")
        let recovered = await history.ingestLog(.wifi, epoch: "abc", records: [record(101), record(102)], requireContiguous: true)
        precondition(recovered && history.wifi.count == 1)
        _ = await history.ingestLog(.wifi, epoch: "abc", records: [record(101), record(102)], requireContiguous: true)
        let live = try ARIAJSONResponse.session([
            "wifi": [["mac": "AA:01", "category": "computer"]],
            "ble": [["address": "BB:01", "category": "phone"]],
            "capabilities": ["detections": [
                ["radio": "wifi", "mac": "AA:02", "category": "computer"],
                ["radio": "ble", "mac": "BB:02", "category": "phone"],
                ["radio": "ble", "mac": "BB:03", "category": "alpr_camera"]
            ]],
            "subghz": [
                ["sequence": 1, "boot": 7, "replay_eligible": true, "decode": ["decoded_status": "UNKNOWN"]],
                ["sequence": 2, "boot": 7, "replay_eligible": false, "decode": ["decoded_status": "VERIFIED"]],
                ["sequence": 3, "boot": 7, "decode": ["decoded_status": "VERIFIED"]]
            ],
            "uas": ["observations": [["uas_id": "RID", "validation": true, "classification": "VALIDATED_REMOTE_ID", "id_type": 1, "lat": 42.0]]]
        ])
        await history.ingestLive(live)
        let flash: [String: Any] = ["seq": 1, "boot": 42, "capture_id": "subghz-def-1", "radio_sequence": 1, "radio_boot_id": 7, "decode_state": "UNKNOWN", "pulses": "waveform"]
        _ = await history.ingestLog(.subghz, epoch: "def", records: [flash], requireContiguous: true)
        let rows = history.overviewCatalog().rows(connected: true)
        precondition(rows.first { $0.id == "computer" }?.total == 2)
        precondition(rows.first { $0.id == "phone" }?.total == 2)
        precondition(rows.first { $0.id == "alpr_camera" }?.total == 1)
        precondition(rows.first { $0.id == "drone" }?.total == 1)
        precondition(rows.first { $0.id == "subghz_replayable" }?.total == 1, "Log backfill preserves eligibility; decoding alone is insufficient")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aria-session-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let counts = try await history.writeExport(to: url, metadata: ["through_sequence": ["wifi": 102]])
        let exported = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        precondition(exported["schema"] as? String == "aria.boot-session.v1")
        precondition(exported["boot_id"] as? Int == 42)
        let observations = exported["observations"] as! [[String: Any]]
        precondition(observations.count == 3 && observations.allSatisfy { $0["boot"] as? Int == 42 })
        precondition(observations.filter { $0["mac"] as? String == "AA:01" }.count == 2, "Repeated sightings survive export without duplicate paging")
        for source in ARIALogSource.allCases {
            precondition((exported[source.rawValue] as! [Any]).count == counts[source])
        }
        await history.beginSession(boot: 43)
        precondition(ARIALogSource.allCases.allSatisfy { history.total($0) == 0 })
        precondition(history.overviewCatalog().records.isEmpty && history.cursors.isEmpty)
        let relaunched = ARIAHistory()
        precondition(relaunched.bootID == nil && relaunched.wifi.isEmpty)
        print("PASS: boot filtering/reset, complete sequences, repeated observations, export metadata/counts, unified categories and replay eligibility")
    }
}
