import Foundation
import CoreLocation

enum RFSourceKind: String, Codable, Hashable, CaseIterable {
    case ble
    case wifiHost
    case sdr
    case acoustic
    case optical
    case uwb
    case synthetic
    case meshPeer
    case droneRF
}

enum RFDeviceClass: String, Codable, Hashable, CaseIterable {
    case unknown
    case phone
    case laptop
    case airtag
    case flipper
    case hackrf
    case drone
    case droneController
    case camera
    case iot
    case zigbee
    case lora
    case vehicleTPMS
    case other
}

struct RFSourceHit: Codable, Hashable, Identifiable {
    var id: String { "\(kind.rawValue)-\(label)-\(timestamp.timeIntervalSince1970)" }
    var kind: RFSourceKind
    var label: String
    var confidence: Double
    var timestamp: Date
}

struct RFTrack: Identifiable, Codable, Hashable {
    var id: UUID
    var displayName: String
    var deviceClass: RFDeviceClass
    var sources: [RFSourceHit]
    var rssi: Int?
    var estimatedDistanceM: Double?
    var bearingDeg: Double?
    var latitude: Double?
    var longitude: Double?
    var threatScore: Int
    var threatReasons: [String]
    var anomalyScore: Double
    var firstSeen: Date
    var lastSeen: Date
    var isSynthetic: Bool
    var linkedBLEId: UUID?
    var linkedHostIP: String?
    var droneMeta: DroneTrackMeta?
    var behaviourNotes: [String]

    var primarySource: RFSourceKind {
        sources.sorted { $0.confidence > $1.confidence }.first?.kind ?? .ble
    }

    var threatBand: String {
        switch threatScore {
        case 8...10: return "CRITICAL"
        case 5...7: return "ELEVATED"
        case 3...4: return "WATCH"
        default: return "NOMINAL"
        }
    }
}

struct DroneTrackMeta: Codable, Hashable {
    var vendorGuess: String?
    var linkType: String?
    var remoteIdPresent: Bool
    var mavlinkPortOpen: Bool
    var controllerNearby: Bool
}
