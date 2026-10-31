import Foundation
import CoreLocation
import Observation
import UIKit

/// Phone GPS for the live proximity map. BLE has no bearing — we only get approximate range from RSSI.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus
    private(set) var latestFix: CLLocation?
    var coordinate: CLLocationCoordinate2D?
    var headingDegrees: CLLocationDirection?
    var headingAccuracyDegrees: Double?
    var headingReference = "unavailable"
    var accuracyMeters: CLLocationAccuracy?
    var errorMessage: String?

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.headingFilter = 1
        NotificationCenter.default.addObserver(self, selector: #selector(updateHeadingOrientation),
                                              name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    func requestAndStart() {
        errorMessage = nil
        updateHeadingOrientation()
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        case .denied, .restricted:
            errorMessage = "Location denied — enable in Settings → Finch → Location."
        @unknown default:
            errorMessage = "Location unavailable."
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        headingDegrees = nil
        headingAccuracyDegrees = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if !isAuthorized {
            latestFix = nil
            headingDegrees = nil
            headingAccuracyDegrees = nil
            coordinate = nil
            accuracyMeters = nil
        }
        if isAuthorized {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        coordinate = loc.coordinate
        if loc.horizontalAccuracy < 0 {
            latestFix = nil
            accuracyMeters = nil
            coordinate = nil
            BLEEvidenceSanitizer.logCatch("CLLocation horizontalAccuracy=\(loc.horizontalAccuracy) invalid — GPS not ingested")
            return
        }
        latestFix = loc
        accuracyMeters = loc.horizontalAccuracy
        errorMessage = nil
        BLESurveyFix.ingest(loc)
    }

    @objc private func updateHeadingOrientation() {
        switch UIDevice.current.orientation {
        case .portrait: manager.headingOrientation = .portrait
        case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
        case .landscapeLeft: manager.headingOrientation = .landscapeLeft
        case .landscapeRight: manager.headingOrientation = .landscapeRight
        default: break // Flat/unknown: retain the last valid screen orientation.
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else {
            headingDegrees = nil
            headingAccuracyDegrees = nil
            headingReference = "unavailable"
            return
        }
        headingAccuracyDegrees = newHeading.headingAccuracy
        if newHeading.trueHeading >= 0 {
            headingDegrees = newHeading.trueHeading
            headingReference = "true north"
        } else if newHeading.magneticHeading >= 0 {
            headingDegrees = newHeading.magneticHeading
            headingReference = "magnetic north"
        } else {
            headingDegrees = nil
            headingReference = "unavailable"
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}

enum BLESurveyFix {
    static var latitude: Double?
    static var longitude: Double?
    static var accuracyMeters: Double?
    /// The one phone location/CLHeading source every view reads. CLLocationManager delivers
    /// delegate callbacks on the run loop of the thread that created it, and the first touch
    /// can come from the BLE queue (BLEDevice init → ObservationLocation.capture), which has
    /// no run loop — heading then never arrives ("Compass unavailable"). Always build on main.
    static let location: LocationProvider = Thread.isMainThread
        ? LocationProvider()
        : DispatchQueue.main.sync { LocationProvider() }

    static func ingest(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0 else {
            BLEEvidenceSanitizer.logCatch("BLESurveyFix skipped invalid GPS accuracy \(loc.horizontalAccuracy)")
            return
        }
        latitude = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        accuracyMeters = loc.horizontalAccuracy
    }

    static func startIfNeeded() {
        location.requestAndStart()
    }
}

enum ProximityGeo {
    /// Stable pseudo-bearing so a device keeps roughly the same map angle while RSSI distance updates.
    static func bearingDegrees(for id: UUID) -> Double {
        var hasher = Hasher()
        hasher.combine(id)
        let h = UInt64(bitPattern: Int64(hasher.finalize()))
        return Double(h % 360)
    }

    static func coordinate(
        from origin: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let R = 6_378_137.0
        let d = max(distanceMeters, 0.5)
        let brng = bearingDegrees * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d / R) + cos(lat1) * sin(d / R) * cos(brng))
        let lon2 = lon1 + atan2(
            sin(brng) * sin(d / R) * cos(lat1),
            cos(d / R) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

/// A frozen collector fix, never a target coordinate. Timestamp strings are UTC
/// ISO-8601 regardless of the surrounding export's date encoding strategy.
struct ObservationLocation: Codable, Hashable {
    var source = "iphone_core_location"
    var positionRole = "collector_not_target"
    var correlation = "phone_received_at"
    var receivedAt: String
    var status: String
    var fixTimestamp: String?
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracyMeters: Double?
    var altitudeMeters: Double?
    var verticalAccuracyMeters: Double?
    var ageSeconds: Double?

    static func capture(at now: Date = Date()) -> ObservationLocation {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var result = ObservationLocation(receivedAt: formatter.string(from: now), status: "unavailable")
        let provider = BLESurveyFix.location
        guard provider.isAuthorized else {
            result.status = "permission_unavailable"
            return result
        }
        guard let fix = provider.latestFix else { return result }
        let age = now.timeIntervalSince(fix.timestamp)
        result.fixTimestamp = formatter.string(from: fix.timestamp)
        result.ageSeconds = age
        guard age >= -1, age <= 15, fix.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(fix.coordinate) else {
            result.status = "stale_or_invalid"
            return result
        }
        result.status = "available"
        result.latitude = fix.coordinate.latitude
        result.longitude = fix.coordinate.longitude
        result.horizontalAccuracyMeters = fix.horizontalAccuracy
        if fix.verticalAccuracy >= 0 {
            result.altitudeMeters = fix.altitude
            result.verticalAccuracyMeters = fix.verticalAccuracy
        }
        return result
    }
}

/// Keeps the first receipt fix for unchanged firmware records, so exporting or
/// polling an old capture cannot move it to the phone's current location.
struct ARIAObservationGeotagger {
    private var previous: [Data: ObservationLocation] = [:]

    mutating func annotate(_ data: Data, fix: ObservationLocation) throws -> Data {
        var root = try ARIAJSONResponse.object(data, endpoint: "GPS export")
        var retained: [Data: ObservationLocation] = [:]
        for band in ["wifi", "ble", "subghz", "captures", "uas", "rfid"] {
            guard let records = root[band] as? [Any] else { continue }
            root[band] = try records.map { value -> Any in
                guard var record = value as? [String: Any] else { return value }
                let key = try JSONSerialization.data(withJSONObject: ["band": band, "record": record], options: [.sortedKeys])
                let receipt = previous[key] ?? fix
                retained[key] = receipt
                record["finch_collection"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt))
                return record
            }
        }
        previous = retained
        root["finch_collection_schema"] = "finch.collector-location.v1"
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
