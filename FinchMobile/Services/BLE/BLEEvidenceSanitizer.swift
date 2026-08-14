import Foundation
import os

/// Distinguishes “never observed” from “observed, empty” so JSON never uses "Unknown" as a stand-in.
enum ObservationStatus: String, Codable, Hashable {
    case notChecked = "not_checked"
    case notAvailable = "not_available"
    case present
}

/// CoreBluetooth / CoreLocation sentinel handling + bounds checks before a record is persisted or exported.
///
/// Apple: `CBPeripheral` RSSI `127` means RSSI unavailable.
/// Apple: `CLLocation.horizontalAccuracy` < 0 means lat/lon are invalid.
/// BLE Core Spec: Tx Power Level AD is a signed dBm typically in [-127, +20]; `127` is not a valid TX level.
enum BLEEvidenceSanitizer {
    static let rssiUnavailableSentinel = 127
    static let rssiMinValid = -100
    static let rssiMaxValid = 0
    static let txPowerMinValid = -127
    static let txPowerMaxValid = 20
    static let gpsAccuracyMinValid = 0.0
    /// Reject absurd reported accuracy (still “positive” but not a real GPS fix).
    static let gpsAccuracyMaxValid = 50_000.0

    private static let log = OSLog(subsystem: "com.aetherverse.finch", category: "BLEEvidenceSanitizer")

    @discardableResult
    static func logCatch(_ message: String) -> String {
        os_log("%{public}@", log: log, type: .error, "[BLEEvidenceSanitizer] \(message)")
        return message
    }

    /// CoreBluetooth RSSI: 127 → null. Out of [-100, 0] → null. Never coerce to 0 or keep last-known.
    static func sanitizeRSSI(_ raw: Int?, field: String = "rssi") -> Int? {
        guard let raw else { return nil }
        if raw == rssiUnavailableSentinel {
            logCatch("\(field)=127 (CoreBluetooth RSSI unavailable) → null")
            return nil
        }
        if raw < rssiMinValid || raw > rssiMaxValid {
            logCatch("\(field)=\(raw) outside [\(rssiMinValid), \(rssiMaxValid)] → null")
            return nil
        }
        return raw
    }

    static func sanitizeTxPower(_ raw: Int?) -> Int? {
        guard let raw else { return nil }
        if raw == rssiUnavailableSentinel {
            logCatch("txPower=127 (invalid / unavailable) → null")
            return nil
        }
        if raw < txPowerMinValid || raw > txPowerMaxValid {
            logCatch("txPower=\(raw) outside [\(txPowerMinValid), \(txPowerMaxValid)] dBm → null")
            return nil
        }
        return raw
    }

    /// Apple: negative horizontalAccuracy means the location is invalid.
    static func sanitizeGPSAccuracy(_ raw: Double?) -> Double? {
        guard let raw else { return nil }
        if raw < gpsAccuracyMinValid {
            logCatch("gpsAccuracyMeters=\(raw) (CLLocationAccuracy negative = invalid) → null")
            return nil
        }
        if raw > gpsAccuracyMaxValid {
            logCatch("gpsAccuracyMeters=\(raw) exceeds \(gpsAccuracyMaxValid) m → null")
            return nil
        }
        return raw
    }

    static func sanitizeCoordinate(lat: Double?, lon: Double?, accuracy: Double?) -> (Double?, Double?, Double?) {
        let acc = sanitizeGPSAccuracy(accuracy)
        guard acc != nil, let lat, let lon else {
            if lat != nil || lon != nil {
                logCatch("GPS lat/lon dropped because accuracy is invalid or missing")
            }
            return (nil, nil, nil)
        }
        if lat < -90 || lat > 90 || lon < -180 || lon > 180 {
            logCatch("GPS coordinate out of range lat=\(lat) lon=\(lon) → null")
            return (nil, nil, nil)
        }
        return (lat, lon, acc)
    }

    /// Empty string is not a name. nil vs empty: both become (nil, status).
    /// - `sourceNil`: field was never populated (e.g. GATT not read) → `not_checked`
    /// - empty or whitespace: queried, nothing found → `not_available`
    static func sanitizeName(_ raw: String?, sourceNilMeans: ObservationStatus) -> (String?, ObservationStatus) {
        guard let raw else { return (nil, sourceNilMeans) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            logCatch("empty name string treated as not_available (not a placeholder)")
            return (nil, .notAvailable)
        }
        let lowered = trimmed.lowercased()
        if lowered == "unknown" || lowered == "n/a" || lowered == "none" {
            logCatch("placeholder name \"\(trimmed)\" rejected → not_available")
            return (nil, .notAvailable)
        }
        return (trimmed, .present)
    }

    static func mergeRSSIExtrema(current: Int?, incoming: Int?, peak: Int?, floor: Int?) -> (rssi: Int?, peak: Int?, min: Int?) {
        let rssi = incoming
        var newPeak = peak
        var newFloor = floor
        if let incoming {
            newPeak = newPeak.map { max($0, incoming) } ?? incoming
            newFloor = newFloor.map { min($0, incoming) } ?? incoming
        }
        _ = current
        return (rssi, newPeak, newFloor)
    }

    static func sanitizeTimestamp(_ date: Date?, now: Date = Date()) -> Date? {
        guard let date else { return nil }
        let interval = date.timeIntervalSince1970
        if interval <= 0 {
            logCatch("timestamp epoch/sentinel \(interval) → null")
            return nil
        }
        if date > now.addingTimeInterval(3600) {
            logCatch("timestamp in the future \(date) → null")
            return nil
        }
        return date
    }

    struct DevicePatch {
        var rssi: Int?
        var rssiPeak: Int?
        var rssiMin: Int?
        var txPower: Int?
        var latitude: Double?
        var longitude: Double?
        var gpsAccuracyMeters: Double?
        var name: String?
        var nameStatus: ObservationStatus
        var localName: String?
        var localNameStatus: ObservationStatus
        var gattDeviceName: String?
        var gattDeviceNameStatus: ObservationStatus
        var lastSeen: Date?
        var firstSeen: Date?
        var catches: [String]
    }

    static func sanitizeDeviceFields(
        rssi: Int?,
        rssiPeak: Int?,
        rssiMin: Int?,
        txPower: Int?,
        latitude: Double?,
        longitude: Double?,
        gpsAccuracyMeters: Double?,
        name: String?,
        localName: String?,
        gattDeviceName: String?,
        gattWasChecked: Bool,
        lastSeen: Date?,
        firstSeen: Date?
    ) -> DevicePatch {
        let rssiS = sanitizeRSSI(rssi)
        let peakS = sanitizeRSSI(rssiPeak, field: "rssiPeak")
        let minS = sanitizeRSSI(rssiMin, field: "rssiMin")
        let txS = sanitizeTxPower(txPower)
        let (lat, lon, acc) = sanitizeCoordinate(lat: latitude, lon: longitude, accuracy: gpsAccuracyMeters)
        let (n, ns) = sanitizeName(name, sourceNilMeans: .notAvailable)
        let (ln, lns) = sanitizeName(localName, sourceNilMeans: .notAvailable)
        let (gn, gns) = sanitizeName(gattDeviceName, sourceNilMeans: gattWasChecked ? .notAvailable : .notChecked)
        let last = sanitizeTimestamp(lastSeen)
        let first = sanitizeTimestamp(firstSeen)
        return DevicePatch(
            rssi: rssiS,
            rssiPeak: peakS,
            rssiMin: minS,
            txPower: txS,
            latitude: lat,
            longitude: lon,
            gpsAccuracyMeters: acc,
            name: n,
            nameStatus: ns,
            localName: ln,
            localNameStatus: lns,
            gattDeviceName: gn,
            gattDeviceNameStatus: gns,
            lastSeen: last,
            firstSeen: first,
            catches: []
        )
    }
}
