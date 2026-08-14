import Foundation
import CoreLocation
import Observation

/// Phone GPS for the live proximity map. BLE has no bearing — we only get approximate range from RSSI.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus
    var coordinate: CLLocationCoordinate2D?
    var headingDegrees: CLLocationDirection?
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
        manager.headingFilter = 5
    }

    func requestAndStart() {
        errorMessage = nil
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
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
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
            accuracyMeters = nil
            coordinate = nil
            BLEEvidenceSanitizer.logCatch("CLLocation horizontalAccuracy=\(loc.horizontalAccuracy) invalid — GPS not ingested")
            return
        }
        accuracyMeters = loc.horizontalAccuracy
        errorMessage = nil
        BLESurveyFix.ingest(loc)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.trueHeading >= 0 {
            headingDegrees = newHeading.trueHeading
        } else if newHeading.magneticHeading >= 0 {
            headingDegrees = newHeading.magneticHeading
        } else {
            headingDegrees = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}

enum BLESurveyFix {
    static var latitude: Double?
    static var longitude: Double?
    static var accuracyMeters: Double?
    static let location = LocationProvider()

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
