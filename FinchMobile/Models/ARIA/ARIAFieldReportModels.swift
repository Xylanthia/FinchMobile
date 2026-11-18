import Foundation
import CoreFoundation
import CryptoKit

/// A report is a projection of one exported JSON object. Missing source fields stay nil;
/// rendering code omits them rather than filling them with guesses or "N/A" placeholders.
struct ARIAFieldReportDocument {
    struct Coordinate {
        let latitude: Double
        let longitude: Double
        var display: String { String(format: "%.6f, %.6f", latitude, longitude) }
    }

    struct RadioObservation: Identifiable {
        let id: String
        let band: String
        let address: String?
        let vendor: String?
        let name: String?
        let distanceFeet: Double?
        let rssi: Int?
        let classification: String?
        let threatLevel: String?
        let timestamp: String?
        let isRandomizedAddress: Bool
        let bodyCameraMaker: String?

        var isAnonymous: Bool { address == nil || isRandomizedAddress }
    }

    struct SubGHzSignal: Identifiable {
        let id: String
        let captureID: String?
        let frequencyMHz: Double?
        let modulation: String?
        let rssi: Int?
        let timestamp: String?
        let replayEligible: Bool?
        let rawPulseData: String?
    }

    struct OSINTFinding: Identifiable {
        let id: String
        let source: String?
        let kind: String?
        let value: String?
        let note: String?
        let isAlert: Bool
    }

    struct OSINTSection {
        let query: String?
        let address: String?
        let ownerName: String?
        let propertyGPS: Coordinate?
        let findings: [OSINTFinding]
    }

    struct Anomaly: Identifiable {
        let id: String
        let title: String
        let device: String
        let detail: String
        let severity: Severity

        enum Severity { case critical, high, review, info }

        var threatLevelLabel: String {
            switch severity {
            case .critical: return "CRITICAL"
            case .high: return "HIGH"
            case .review: return "REVIEW"
            case .info: return "INFO"
            }
        }
    }

    let generatedAt: Date
    let exportTimestamp: String?
    let operatorID: String?
    let operatorGPS: Coordinate?
    let wifi: [RadioObservation]
    let ble: [RadioObservation]
    let subGHz: [SubGHzSignal]
    let osint: OSINTSection?
    let anomalies: [Anomaly]
    let originalJSON: Data
    let exportSHA256: String
    let sourceExportSHA256: String?

    var totalRadioDevices: Int { wifi.count + ble.count }

    /// Counts distinct randomized addresses. Rows without an address remain countable
    /// individually when the source explicitly marks them as randomized.
    var randomizedMACCount: Int {
        Self.randomizedAddressCount(wifi + ble)
    }

    private static func randomizedAddressCount(_ observations: [RadioObservation]) -> Int {
        let rows = observations.filter(\.isRandomizedAddress)
        let addresses = Set(rows.compactMap { $0.address?.uppercased() })
        let addresslessRows = rows.filter { $0.address == nil }.count
        return addresses.count + addresslessRows
    }

    var replayEligibleSignals: [SubGHzSignal] {
        subGHz.filter { $0.replayEligible == true }
    }

    init(jsonData: Data, operatorID overrideOperatorID: String? = nil) throws {
        let value = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])
        guard let root = value as? [String: Any] else {
            throw ParseError.expectedObject
        }

        let decodedWifi = Self.radioRows(root: root, band: "wifi")
        let decodedBLE = Self.radioRows(root: root, band: "ble")
        let decodedSubGHz = Self.subGHzRows(root: root)

        generatedAt = Date()
        exportTimestamp = Self.firstString(in: root, keys: ["exported_at", "generated_at", "capture_timestamp", "timestamp"])
        operatorID = Self.nonEmpty(overrideOperatorID) ?? Self.firstString(in: root, keys: ["operator_id", "operatorId"])
        operatorGPS = Self.coordinate(in: root["operator_gps"] ?? root["operator_location"])
        wifi = decodedWifi
        ble = decodedBLE
        subGHz = decodedSubGHz
        osint = Self.osintSection(in: root)
        anomalies = Self.findAnomalies(wifi: decodedWifi, ble: decodedBLE, subGHz: decodedSubGHz)
        originalJSON = jsonData
        exportSHA256 = Self.sha256ForInput(jsonData)
        sourceExportSHA256 = Self.firstString(in: root, keys: ["source_export_sha256"])
    }

    enum ParseError: LocalizedError {
        case expectedObject
        var errorDescription: String? { "The field-report source must be a JSON object." }
    }

    // MARK: - JSON extraction

    private static func radioRows(root: [String: Any], band: String) -> [RadioObservation] {
        let keys = band == "wifi" ? ["wifi", "wifi_devices"] : ["ble", "bluetooth", "ble_devices"]
        var candidates = arrays(in: root, keys: keys)
        if candidates.isEmpty {
            let session = root["session"] as? [String: Any] ?? [:]
            candidates = arrays(in: session, keys: keys)
            if let devices = session["devices"] as? [[String: Any]] {
                candidates += devices.filter { bandName($0) == band }
            }
        }
        if candidates.isEmpty, let observations = root["observations"] as? [[String: Any]] {
            candidates = observations.filter { bandName($0) == band }
        }
        if candidates.isEmpty, let devices = root["devices"] as? [[String: Any]] {
            candidates = devices.filter { bandName($0) == band }
        }

        return candidates.enumerated().compactMap { index, wrapper in
            let row = mergedRecord(wrapper)
            let address = firstString(in: row, keys: ["mac", "address", "bssid"])
            let nameKeys = band == "wifi" ? ["ssid", "name", "device_name"] : ["name", "local_name", "device_name"]
            let name = firstString(in: row, keys: nameKeys)
            let decode = row["decode"] as? [String: Any] ?? [:]
            let fingerprint = bestFingerprint(in: decode)
            let vendor = firstString(in: row, keys: ["vendor", "manufacturer", "company_name"])
                ?? firstString(in: fingerprint, keys: ["vendor", "manufacturer"])
            let rssi = integer(in: row, keys: ["rssi", "avg_rssi"])
            let category = firstString(in: row, keys: ["category", "device_class", "class", "device_type"])
                ?? firstString(in: fingerprint, keys: ["device_class", "class"])
            let mac = address
            let randomField = boolean(in: row, keys: ["randomized", "rand", "rand_mac", "random_address"])
            let isRandomized = randomField ?? Self.isLocallyAdministered(mac) ?? false
            let companyID = firstString(in: row, keys: ["company_id", "companyID"])
            let adHex = firstString(in: decode, keys: ["raw_hex"])
            let camera = ARIABodyCam.match(mac: mac, companyID: companyID, advHex: adHex)?.maker

            return RadioObservation(
                id: "\(band)-\(address ?? "row-\(index)")-\(index)",
                band: band.uppercased(),
                address: address,
                vendor: vendor,
                name: name,
                distanceFeet: distance(in: row),
                rssi: rssi,
                classification: category,
                threatLevel: firstString(in: row, keys: ["threat_level", "severity", "risk_level"]),
                timestamp: firstString(in: row, keys: ["timestamp", "seen_at", "last_seen", "last_seen_at", "phone_last_received", "captured_at"]),
                isRandomizedAddress: isRandomized,
                bodyCameraMaker: camera
            )
        }
    }

    private static func subGHzRows(root: [String: Any]) -> [SubGHzSignal] {
        var candidates = arrays(in: root, keys: ["subghz", "sub_ghz", "subghz_signals"])
        if candidates.isEmpty, let captures = root["captures"] as? [String: Any] {
            candidates = arrays(in: captures, keys: ["subghz", "sub_ghz"])
        }
        if candidates.isEmpty, let session = root["session"] as? [String: Any] {
            candidates = arrays(in: session, keys: ["subghz", "sub_ghz"])
        }
        if candidates.isEmpty, let observations = root["observations"] as? [[String: Any]] {
            candidates = observations.filter { bandName($0) == "subghz" || $0["frequency_mhz"] != nil || $0["mhz"] != nil }
        }
        if candidates.isEmpty, let devices = root["devices"] as? [[String: Any]] {
            candidates = devices.filter { bandName($0) == "subghz" }
        }

        // Live API exports sometimes wrap packet rows in subghz_live.packets.
        if candidates.isEmpty, let live = root["subghz_live"] as? [String: Any] {
            candidates = arrays(in: live, keys: ["packets", "captures"])
        }

        return candidates.enumerated().map { index, wrapper in
            let row = mergedRecord(wrapper)
            let decode = row["decode"] as? [String: Any] ?? [:]
            let frequency = decimal(in: row, keys: ["frequency_mhz", "mhz", "frequency"])
            let modulation = firstString(in: row, keys: ["modulation", "rx_modulation", "mod", "profile", "encoding"])
            let eligible = boolean(in: row, keys: ["replay_eligible"])
            let raw = firstPresent(in: row, keys: ["raw_pulses", "raw_durations_us", "pulse_durations_us", "durations_us", "pulses", "raw_hex"])
                ?? firstPresent(in: decode, keys: ["raw_hex", "raw_pulses", "pulse_durations_us"])
            return SubGHzSignal(
                id: "subghz-\(firstString(in: row, keys: ["sequence", "seq"]) ?? String(index))",
                captureID: firstString(in: row, keys: ["sequence", "seq", "radio_sequence"]),
                frequencyMHz: frequency,
                modulation: modulation,
                rssi: integer(in: row, keys: ["rssi"]),
                timestamp: firstString(in: row, keys: ["timestamp", "captured_at", "seen_at", "phone_last_received"]),
                replayEligible: eligible,
                rawPulseData: raw.map(compactValue)
            )
        }
    }

    private static func osintSection(in root: [String: Any]) -> OSINTSection? {
        let osint = root["osint"] as? [String: Any]
            ?? root["address_lookup"] as? [String: Any]
            ?? root["identity_resolution"] as? [String: Any]
        guard let osint else { return nil }

        var findings = (osint["findings"] as? [[String: Any]] ?? []).enumerated().compactMap { index, row -> OSINTFinding? in
            let source = firstString(in: row, keys: ["source", "provider"])
            let kind = firstString(in: row, keys: ["kind", "type"])
            let value = firstString(in: row, keys: ["value", "name", "title"])
            let note = firstString(in: row, keys: ["note", "detail", "description"])
            guard value != nil || note != nil else { return nil }
            let haystack = "\(source ?? "") \(kind ?? "") \(note ?? "")".lowercased()
            return OSINTFinding(id: "finding-\(index)", source: source, kind: kind, value: value, note: note,
                                isAlert: haystack.contains("hibp") || haystack.contains("breach") || haystack.contains("alert"))
        }
        if let brief = osint["brief"] as? [String] {
            findings += brief.enumerated().compactMap { index, text -> OSINTFinding? in
                guard let text = nonEmpty(text) else { return nil }
                return OSINTFinding(id: "brief-\(index)", source: nil, kind: "Summary", value: text, note: nil, isAlert: false)
            }
        }

        let owner = firstString(in: osint, keys: ["owner_name", "resident_name", "property_owner", "owner"])
            ?? findings.first(where: { ["name", "owner", "resident"].contains(($0.kind ?? "").lowercased()) && ["assessor", "county", "gis"].contains(($0.source ?? "").lowercased()) })?.value
        let propertyGPS = coordinate(in: osint["property_gps"] ?? osint["property_location"] ?? osint["coordinates"])
            ?? findings.first(where: { ["geo", "coordinates", "location"].contains(($0.kind ?? "").lowercased()) })?.value.flatMap(parseCoordinate)
        let address = firstString(in: osint, keys: ["address", "queried_address", "property_address"])
        let query = firstString(in: osint, keys: ["query", "seed", "search_term"])
        let alertRows = (osint["alerts"] as? [[String: Any]] ?? osint["breaches"] as? [[String: Any]] ?? []).enumerated().map { index, row in
            OSINTFinding(id: "alert-\(index)", source: firstString(in: row, keys: ["source", "provider"]) ?? "OSINT alert",
                         kind: firstString(in: row, keys: ["kind", "type"]), value: firstString(in: row, keys: ["name", "title", "value"]),
                         note: firstString(in: row, keys: ["note", "detail", "description"]), isAlert: true)
        }
        let allFindings = findings + alertRows
        guard query != nil || address != nil || owner != nil || propertyGPS != nil || !allFindings.isEmpty else { return nil }
        return OSINTSection(query: query, address: address, ownerName: owner, propertyGPS: propertyGPS, findings: allFindings)
    }

    private static func findAnomalies(wifi: [RadioObservation], ble: [RadioObservation], subGHz: [SubGHzSignal]) -> [Anomaly] {
        var result: [Anomaly] = []
        for device in wifi + ble {
            let identity = [device.vendor, device.name].compactMap { $0 }.joined(separator: " ")
            let subject = identity.isEmpty ? "device" : "\(identity) device"
            let deviceLabel = device.name ?? device.vendor ?? device.classification ?? "Unclassified radio"

            if device.isRandomizedAddress {
                if let rssi = device.rssi, rssi > -50 {
                    result.append(Anomaly(
                        id: "strong-randomized-\(device.id)",
                        title: "Close-proximity randomized address",
                        device: deviceLabel,
                        detail: "A locally administered address was observed at RSSI \(rssi) dBm (stronger than -50 dBm). The address is omitted because it may rotate.",
                        severity: .high
                    ))
                }
                continue
            }

            if let threat = device.threatLevel?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
               threat == "CRITICAL" || threat == "HIGH" {
                result.append(Anomaly(
                    id: "source-threat-\(device.id)",
                    title: "Source threat level reported",
                    device: deviceLabel,
                    detail: "The JSON export labels this observation \(threat). Verify the underlying evidence and source scoring.",
                    severity: threat == "CRITICAL" ? .critical : .high
                ))
            }
            if let maker = device.bodyCameraMaker {
                result.append(Anomaly(id: "bodycam-\(device.id)", title: "Possible body-camera maker identifier", device: deviceLabel,
                                      detail: "\(maker) identifier matched \(device.address.map { "at \($0)" } ?? "in a BLE advertisement"). A maker match does not confirm a camera model or its use.", severity: .high))
            }
            if let distance = device.distanceFeet, distance <= 10, device.classification == nil {
                result.append(Anomaly(id: "near-unclassified-\(device.id)", title: "Unclassified nearby device", device: deviceLabel,
                                      detail: "\(subject.capitalized) detected at an estimated \(format(distance)) ft; the export contains no device classification.", severity: .review))
            } else if let rssi = device.rssi, rssi >= -45, device.classification == nil {
                result.append(Anomaly(id: "strong-unclassified-\(device.id)", title: "Strong unclassified signal", device: deviceLabel,
                                      detail: "\(subject.capitalized) at RSSI \(rssi) dBm; signal strength does not establish physical distance.", severity: .review))
            }
            if let name = device.name, containsSmartDisplayName(name) {
                result.append(Anomaly(id: "display-\(device.id)", title: "Consumer display name observed", device: name,
                                      detail: "Broadcast name: \(name). Confirm whether this device belongs in the authorized inventory.", severity: .info))
            }
        }

        let randomizedCount = randomizedAddressCount(wifi + ble)
        if randomizedCount > 0 {
            result.append(Anomaly(
                id: "randomized-background-summary",
                title: "Background Noise",
                device: "Randomized MAC addresses",
                detail: "Background Noise: \(randomizedCount) locally administered (randomized) MAC addresses detected. Normal for modern mobile devices.",
                severity: .info
            ))
        }

        let signals915 = subGHz.filter { signal in
            guard let frequency = signal.frequencyMHz else { return false }
            return abs(frequency - 915) < 1
        }
        if !signals915.isEmpty {
            result.append(Anomaly(
                id: "915-summary",
                title: "915 MHz Sub-GHz signals (\(signals915.count))",
                device: "915 MHz group",
                detail: "\(signals915.count) signal record(s) were captured near 915 MHz. Review expected regional band use and receiver profile; frequency alone does not identify a transmitter.",
                severity: .review
            ))
        }

        let replayable = subGHz.filter { $0.replayEligible == true }
        if !replayable.isEmpty {
            let grouped = Dictionary(grouping: replayable) { signal -> String in
                signal.frequencyMHz.map { "\(format($0)) MHz" } ?? "Frequency not supplied"
            }
            let frequencies = grouped.keys.sorted {
                let lhs = Double($0.replacingOccurrences(of: " MHz", with: "")) ?? .greatestFiniteMagnitude
                let rhs = Double($1.replacingOccurrences(of: " MHz", with: "")) ?? .greatestFiniteMagnitude
                return lhs == rhs ? $0 < $1 : lhs < rhs
            }.map { frequency in
                let count = grouped[frequency]?.count ?? 0
                return count > 1 ? "\(frequency) (\(count))" : frequency
            }.joined(separator: ", ")
            result.append(Anomaly(
                id: "replay-summary",
                title: "Replay-eligible Sub-GHz signals",
                device: "Sub-GHz group",
                detail: "WARNING: \(replayable.count) Replay-Eligible Sub-GHz Signals Captured (Frequencies: \(frequencies)). Review access-control implications.",
                severity: .high
            ))
        }
        return result
    }

    // MARK: - Field helpers

    private static func arrays(in dictionary: [String: Any], keys: [String]) -> [[String: Any]] {
        for key in keys {
            if let rows = dictionary[key] as? [[String: Any]], !rows.isEmpty { return rows }
        }
        return []
    }

    private static func mergedRecord(_ wrapper: [String: Any]) -> [String: Any] {
        guard let record = wrapper["record"] as? [String: Any] else { return wrapper }
        return wrapper.merging(record) { _, recordValue in recordValue }
    }

    private static func bandName(_ row: [String: Any]) -> String? {
        let value = firstString(in: row, keys: ["band_kind", "band", "source", "radio", "kind"])?.lowercased()
        if ["wifi", "wi-fi", "802.11"].contains(value) { return "wifi" }
        if ["ble", "bluetooth", "bluetooth_le"].contains(value) { return "ble" }
        if ["subghz", "sub-ghz", "sub_ghz"].contains(value) { return "subghz" }
        return nil
    }

    private static func firstString(in dictionary: [String: Any]?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let string = nonEmpty(dictionary[key] as? String) { return string }
            if let number = dictionary[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        }
        return nil
    }

    private static func firstPresent(in dictionary: [String: Any], keys: [String]) -> Any? {
        keys.first(where: { dictionary[$0] != nil }).flatMap { dictionary[$0] }
    }

    private static func integer(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys { if let value = dictionary[key] as? NSNumber { return value.intValue } }
        return nil
    }

    private static func decimal(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? NSNumber { return value.doubleValue }
            if let value = dictionary[key] as? String, let parsed = Double(value) { return parsed }
        }
        return nil
    }

    private static func boolean(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            guard let value = dictionary[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { continue }
            return value.boolValue
        }
        return nil
    }

    private static func distance(in dictionary: [String: Any]) -> Double? {
        if let feet = decimal(in: dictionary, keys: ["estimated_distance_ft", "estimated_distance_feet", "distance_ft", "distance_feet"]) { return feet }
        if let meters = decimal(in: dictionary, keys: ["estimated_distance_m", "distance_meters", "distance_m"]) { return meters * 3.28084 }
        return nil
    }

    private static func coordinate(in value: Any?) -> Coordinate? {
        guard let dictionary = value as? [String: Any],
              let latitude = decimal(in: dictionary, keys: ["latitude", "lat"]),
              let longitude = decimal(in: dictionary, keys: ["longitude", "lon", "lng"]),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func parseCoordinate(_ value: String) -> Coordinate? {
        let numbers = value.split(whereSeparator: { !$0.isNumber && $0 != "." && $0 != "-" }).compactMap { Double($0) }
        guard numbers.count >= 2, (-90...90).contains(numbers[0]), (-180...180).contains(numbers[1]) else { return nil }
        return Coordinate(latitude: numbers[0], longitude: numbers[1])
    }

    private static func bestFingerprint(in decode: [String: Any]) -> [String: Any]? {
        if let best = decode["best_fingerprint"] as? [String: Any] { return best }
        let attempts = decode["fingerprint_attempts"] as? [[String: Any]] ?? []
        return attempts.max {
            (decimal(in: $0, keys: ["confidence"]) ?? 0) < (decimal(in: $1, keys: ["confidence"]) ?? 0)
        }
    }

    private static func compactValue(_ value: Any) -> String {
        if let string = value as? String { return string }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) else { return String(describing: value) }
        return String(decoding: data, as: UTF8.self)
    }

    private static func isLocallyAdministered(_ address: String?) -> Bool? {
        guard let address else { return nil }
        let hex = address.filter(\.isHexDigit)
        guard [12, 16].contains(hex.count), let first = UInt8(hex.prefix(2), radix: 16) else { return nil }
        return first & 0x02 != 0
    }

    private static func containsSmartDisplayName(_ value: String) -> Bool {
        let name = value.lowercased()
        return ["smart tv", "smarttv", "roku", "fire tv", "apple tv", "chromecast", "webos tv", "samsung tv"].contains(where: name.contains)
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func sha256ForInput(_ data: Data) -> String {
        // CryptoKit is available on every supported FinchMobile iOS target.
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Adds only explicitly selected, currently available context to the source JSON.
/// The original ARIA export is not modified on disk; PDF provenance hashes this exact input.
enum ARIAFieldReportInput {
    static func make(source: Data, osint: OsintReport?, includeOSINT: Bool,
                     operatorID: String, operatorLatitude: Double?, operatorLongitude: Double?) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: source, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw ARIAFieldReportDocument.ParseError.expectedObject
        }
        root["source_export_sha256"] = ARIAFieldReportDocument.sha256ForInput(source)
        let id = operatorID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { root["operator_id"] = id }

        if includeOSINT, let report = osint,
           !report.findings.isEmpty || !report.brief.isEmpty || !report.actions.isEmpty || !report.query.isEmpty {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            root["osint"] = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }

        if let lat = operatorLatitude, let lon = operatorLongitude,
           (-90...90).contains(lat), (-180...180).contains(lon) {
            root["operator_gps"] = ["latitude": lat, "longitude": lon]
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .fragmentsAllowed])
    }
}
