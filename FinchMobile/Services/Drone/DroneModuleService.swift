import Foundation
import Observation

/// BLE-name drone list helper. No RF, no MAVLink, no Tx stubs.
@Observable
final class DroneModuleService {
    var detections: [RFTrack] = []
    var statusText: String = "BLE drone names only"

    func bind(consent: ConsentGate, forensic: ForensicLogger) {
        _ = consent
        _ = forensic
    }

    func refresh(from tracks: [RFTrack]) {
        detections = tracks.filter {
            $0.deviceClass == .drone || $0.deviceClass == .droneController
        }
        statusText = detections.isEmpty ? "No drone-class BLE/LAN tracks" : "\(detections.count) drone-class track(s)"
    }
}
