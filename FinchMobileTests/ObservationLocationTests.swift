import XCTest
@testable import FinchMobile

final class ObservationLocationTests: XCTestCase {
    func testUnchangedFirmwareObservationKeepsReceiptFix() throws {
        var tagger = ARIAObservationGeotagger()
        let raw = Data(#"{"wifi":[{"mac":"aa","rssi":-60}],"captures":[{"sequence":1}],"uas":[{"uas_id":"drone","latitude":20,"longitude":30}]}"#.utf8)
        var first = ObservationLocation(receivedAt: "2026-10-27T12:00:00Z", status: "available")
        first.latitude = 40
        first.longitude = -74
        first.horizontalAccuracyMeters = 5
        _ = try tagger.annotate(raw, fix: first)
        var later = first
        later.receivedAt = "2026-10-27T12:01:00Z"
        later.latitude = 41
        let data = try tagger.annotate(raw, fix: later)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for band in ["wifi", "captures", "uas"] {
            let rows = try XCTUnwrap(root[band] as? [[String: Any]])
            let gps = try XCTUnwrap(rows.first?["finch_collection"] as? [String: Any])
            XCTAssertEqual(gps["latitude"] as? Double, 40)
            XCTAssertEqual(gps["receivedAt"] as? String, first.receivedAt)
        }
        let uas = try XCTUnwrap(root["uas"] as? [[String: Any]])
        XCTAssertEqual(uas.first?["latitude"] as? Int, 20) // target coordinate remains intact
    }

    func testChangedObservationGetsNewReceiptAndMissingGPSStaysExplicit() throws {
        var tagger = ARIAObservationGeotagger()
        let first = ObservationLocation(receivedAt: "first", status: "available")
        _ = try tagger.annotate(Data(#"{"ble":[{"address":"aa","rssi":-60}]}"#.utf8), fix: first)
        let missing = ObservationLocation(receivedAt: "second", status: "permission_unavailable")
        let data = try tagger.annotate(Data(#"{"ble":[{"address":"aa","rssi":-70},"malformed"]}"#.utf8), fix: missing)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(root["ble"] as? [Any])
        let record = try XCTUnwrap(rows.first as? [String: Any])
        let gps = try XCTUnwrap(record["finch_collection"] as? [String: Any])
        XCTAssertEqual(gps["status"] as? String, "permission_unavailable")
        XCTAssertEqual(gps["receivedAt"] as? String, "second")
        XCTAssertNil(gps["latitude"])
        XCTAssertEqual(rows[1] as? String, "malformed")
    }
}
