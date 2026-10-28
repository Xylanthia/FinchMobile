import Foundation

func check(_ condition: Bool, _ label: String) {
    guard condition else { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}

for payload in ["\n<!doctype html><html>ARIA</html>", "", "null", "true", "42", "\"ready\"", "[]", "{\"devices\":[", "{\"ok\":false,\"error\":\"busy\"}"] {
    do {
        _ = try ARIAJSONResponse.object(Data(payload.utf8), endpoint: "/api/devices")
        fatalError("Accepted invalid session response: \(payload)")
    } catch {
        check(error.localizedDescription.hasPrefix("/api/devices:"), "endpoint-specific error for \(payload.prefix(25))")
        check(!(error as NSError).domain.contains("NSCocoaErrorDomain"), "does not leak NSError 3840")
    }
}
let body = Data(#"{"uptime_ms":12000,"devices":[{"mac":"00:11:22:33:44:55","band":"wifi","rssi":-51,"encrypt":"WPA2","pkts":{"probe":2}},{"mac":"AA:BB:CC:DD:EE:FF","band":"ble","rssi":-60}],"ble":true,"subghz":true,"captures":[]}"#.utf8)
let source = try ARIAJSONResponse.object(body, endpoint: "/api/devices")
let envelope: [String: Any] = ["session": source,
    "subghz_live": ["packets": [["sequence": 12, "boot_id": 4000000000, "mhz": 433.92, "rssi": -68.5, "observation": ["status": "UNKNOWN"]]]],
    "rfid": ["state": "SCANNING", "observations": []],
    "poll_warnings": ["/api/rfid: device busy"]]
let session = try ARIAJSONResponse.session(envelope)
check(session.wifi.count == 1 && session.ble.count == 1, "partition real live-device schema by band")
check(session.wifi[0].encryption == "WPA2" && session.wifi[0].probeCount == 2, "map firmware field names")
check(session.subghz.count == 1 && session.subghz[0].boot == 4000000000, "map Sub-GHz boot and capture identity")
check(session.subghz[0].frequencyMHz == 433.92 && session.subghz[0].rssi == -68, "handle numeric Sub-GHz fields")
check(session.summary?.uptimeSeconds == 12, "map uptime units")
check(session.warnings.count == 1, "retain partial endpoint failures")
let retained = try ARIAJSONResponse.object(session.raw, endpoint: "export")
check(retained["firmware_response"] != nil, "preserve original firmware evidence")
let empty = try ARIAJSONResponse.session(["devices": []])
check(empty.wifi.isEmpty && empty.ble.isEmpty && empty.malformedSkipped == 0, "accept a valid empty snapshot")
let mixed = ARIASessionParser.parse(Data(#"{"wifi":[{"mac":"good"},"bad",{"rssi":-40}],"ble":[]}"#.utf8))
check(mixed.wifi.count == 1 && mixed.malformedSkipped == 2, "retain good records beside malformed records")
// Confirm the recovered snapshot does not depend on parser state after a failure.
let recovered = try ARIAJSONResponse.session(["session": source])
check(recovered.wifi.count == 1, "valid response recovers after malformed responses")
print("All JSON response regressions passed.")
