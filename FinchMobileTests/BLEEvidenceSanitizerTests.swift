import XCTest
@testable import FinchMobile

/// Known-bad CoreBluetooth / CoreLocation / name inputs. Sanitizer must null them out, never pass sentinels through.
final class BLEEvidenceSanitizerTests: XCTestCase {
    func testRSSI127IsNullNotZeroOrLastKnown() {
        XCTAssertNil(BLEEvidenceSanitizer.sanitizeRSSI(127))
        XCTAssertEqual(BLEEvidenceSanitizer.sanitizeRSSI(-60), -60)
        let merged = BLEEvidenceSanitizer.mergeRSSIExtrema(
            current: -55,
            incoming: nil,
            peak: -50,
            floor: -70
        )
        XCTAssertNil(merged.rssi)
        XCTAssertEqual(merged.peak, -50)
        XCTAssertEqual(merged.min, -70)
    }

    func testNegativeGPSAccuracyIsNull() {
        let acc = BLEEvidenceSanitizer.sanitizeGPSAccuracy(-1)
        XCTAssertNil(acc)
        let coord = BLEEvidenceSanitizer.sanitizeCoordinate(lat: 37.7, lon: -122.4, accuracy: -1)
        XCTAssertNil(coord.0)
        XCTAssertNil(coord.1)
        XCTAssertNil(coord.2)
        let ok = BLEEvidenceSanitizer.sanitizeCoordinate(lat: 37.7, lon: -122.4, accuracy: 8)
        XCTAssertEqual(ok.0, 37.7)
        XCTAssertEqual(ok.2, 8)
    }

    func testEmptyNameStringVsNil() {
        let empty = BLEEvidenceSanitizer.sanitizeName("", sourceNilMeans: .notAvailable)
        XCTAssertNil(empty.0)
        XCTAssertEqual(empty.1, .notAvailable)

        let nilAdv = BLEEvidenceSanitizer.sanitizeName(nil, sourceNilMeans: .notAvailable)
        XCTAssertNil(nilAdv.0)
        XCTAssertEqual(nilAdv.1, .notAvailable)

        let nilGatt = BLEEvidenceSanitizer.sanitizeName(nil, sourceNilMeans: .notChecked)
        XCTAssertNil(nilGatt.0)
        XCTAssertEqual(nilGatt.1, .notChecked)

        let real = BLEEvidenceSanitizer.sanitizeName("Pixel 8", sourceNilMeans: .notAvailable)
        XCTAssertEqual(real.0, "Pixel 8")
        XCTAssertEqual(real.1, .present)

        let placeholder = BLEEvidenceSanitizer.sanitizeName("Unknown", sourceNilMeans: .notAvailable)
        XCTAssertNil(placeholder.0)
        XCTAssertEqual(placeholder.1, .notAvailable)
    }

    func testTxPowerSentinelAndBounds() {
        XCTAssertNil(BLEEvidenceSanitizer.sanitizeTxPower(127))
        XCTAssertNil(BLEEvidenceSanitizer.sanitizeTxPower(40))
        XCTAssertEqual(BLEEvidenceSanitizer.sanitizeTxPower(-12), -12)
    }

    func testSanitizeDeviceFieldsCatchesAll() {
        let patch = BLEEvidenceSanitizer.sanitizeDeviceFields(
            rssi: 127,
            rssiPeak: 127,
            rssiMin: 5,
            txPower: 127,
            latitude: 40.0,
            longitude: -74.0,
            gpsAccuracyMeters: -1,
            name: "",
            localName: "Unknown",
            gattDeviceName: nil,
            gattWasChecked: false,
            lastSeen: Date(),
            firstSeen: Date()
        )
        XCTAssertNil(patch.rssi)
        XCTAssertNil(patch.rssiPeak)
        XCTAssertNil(patch.rssiMin)
        XCTAssertNil(patch.txPower)
        XCTAssertNil(patch.latitude)
        XCTAssertNil(patch.gpsAccuracyMeters)
        XCTAssertNil(patch.name)
        XCTAssertEqual(patch.nameStatus, .notAvailable)
        XCTAssertEqual(patch.localNameStatus, .notAvailable)
        XCTAssertEqual(patch.gattDeviceNameStatus, .notChecked)
    }
}
