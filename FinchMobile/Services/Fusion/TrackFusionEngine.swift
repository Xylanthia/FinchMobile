import Foundation
import Observation

/// Fuses BLE + Glass hosts (+ optional synthetic / mesh) into unified RF tracks with threat scores.
@Observable
final class TrackFusionEngine {
    var tracks: [UUID: RFTrack] = [:]
    var statusText: String = "Fusion idle"
    private var rssiHistory: [UUID: [Int]] = [:]
    private weak var forensic: ForensicLogger?

    var sortedTracks: [RFTrack] {
        tracks.values.sorted {
            if $0.threatScore != $1.threatScore { return $0.threatScore > $1.threatScore }
            return $0.lastSeen > $1.lastSeen
        }
    }

    var elevatedCount: Int { tracks.values.filter { $0.threatScore >= 5 }.count }

    func bind(forensic: ForensicLogger) { self.forensic = forensic }

    func ingestBLE(_ devices: [BLEDevice]) {
        let now = Date()
        for device in devices {
            let classGuess = ThreatScorer.classifyBLE(device)
            let key = device.identifier
            var hist = rssiHistory[key] ?? []
            hist.append(device.rssi)
            if hist.count > 24 { hist.removeFirst(hist.count - 24) }
            rssiHistory[key] = hist

            let distance = estimateDistanceM(rssi: device.rssi, txPower: device.txPower)
            var track = tracks[key] ?? RFTrack(
                id: key,
                displayName: device.displayName,
                deviceClass: classGuess,
                sources: [],
                rssi: device.rssi,
                estimatedDistanceM: distance,
                bearingDeg: nil,
                latitude: nil,
                longitude: nil,
                threatScore: 1,
                threatReasons: [],
                anomalyScore: 0,
                firstSeen: device.lastSeen,
                lastSeen: now,
                isSynthetic: false,
                linkedBLEId: key,
                linkedHostIP: nil,
                droneMeta: nil,
                behaviourNotes: []
            )
            track.displayName = device.displayName
            track.deviceClass = classGuess
            track.rssi = device.rssi
            track.estimatedDistanceM = distance
            track.lastSeen = now
            track.linkedBLEId = key
            upsertSource(&track, kind: .ble, label: device.shortUUID, confidence: 0.85)

            if classGuess == .drone || classGuess == .droneController {
                track.droneMeta = DroneTrackMeta(
                    vendorGuess: device.manufacturerName ?? device.friendly.deviceType,
                    linkType: "BLE",
                    remoteIdPresent: false,
                    mavlinkPortOpen: false,
                    controllerNearby: classGuess == .droneController
                )
            }

            let (score, reasons, anomaly) = ThreatScorer.score(track: track, history: hist)
            track.threatScore = score
            track.threatReasons = reasons
            track.anomalyScore = anomaly
            tracks[key] = track
        }
        pruneStale(olderThan: 180)
        statusText = "\(tracks.count) tracks · \(elevatedCount) elevated"
    }

    func ingestHosts(_ hosts: [IoTHost]) {
        for host in hosts {
            let classGuess = ThreatScorer.classifyHost(host)
            // Stable UUID from IP
            let key = uuidFromString(host.ip)
            var track = tracks[key] ?? RFTrack(
                id: key,
                displayName: host.hostname ?? host.ip,
                deviceClass: classGuess,
                sources: [],
                rssi: nil,
                estimatedDistanceM: nil,
                bearingDeg: nil,
                latitude: nil,
                longitude: nil,
                threatScore: 1,
                threatReasons: [],
                anomalyScore: 0,
                firstSeen: Date(),
                lastSeen: Date(),
                isSynthetic: false,
                linkedBLEId: nil,
                linkedHostIP: host.ip,
                droneMeta: nil,
                behaviourNotes: []
            )
            track.displayName = host.hostname ?? host.ip
            track.deviceClass = classGuess
            track.lastSeen = Date()
            track.linkedHostIP = host.ip
            upsertSource(&track, kind: .wifiHost, label: host.ip, confidence: 0.9)

            let mavOpen = host.openPorts.contains { (5760...5763).contains($0) }
            if classGuess == .drone || mavOpen {
                track.droneMeta = DroneTrackMeta(
                    vendorGuess: host.fingerprint?.vendor ?? host.vendor,
                    linkType: "LAN/TCP",
                    remoteIdPresent: false,
                    mavlinkPortOpen: mavOpen,
                    controllerNearby: false
                )
                track.deviceClass = .drone
            }

            let (score, reasons, anomaly) = ThreatScorer.score(track: track, history: [])
            track.threatScore = score
            track.threatReasons = reasons
            track.anomalyScore = anomaly
            tracks[key] = track
        }
        statusText = "\(tracks.count) tracks · \(elevatedCount) elevated"
    }

    func injectSynthetic(
        name: String,
        deviceClass: RFDeviceClass,
        threatBoost: Int = 0,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> RFTrack {
        let id = UUID()
        var track = RFTrack(
            id: id,
            displayName: name,
            deviceClass: deviceClass,
            sources: [RFSourceHit(kind: .synthetic, label: "research", confidence: 1.0, timestamp: Date())],
            rssi: -55,
            estimatedDistanceM: 8,
            bearingDeg: Double.random(in: 0..<360),
            latitude: latitude,
            longitude: longitude,
            threatScore: 1,
            threatReasons: [],
            anomalyScore: 0.2,
            firstSeen: Date(),
            lastSeen: Date(),
            isSynthetic: true,
            linkedBLEId: nil,
            linkedHostIP: nil,
            droneMeta: deviceClass == .drone ? DroneTrackMeta(
                vendorGuess: "Synthetic",
                linkType: "SIM",
                remoteIdPresent: true,
                mavlinkPortOpen: false,
                controllerNearby: true
            ) : nil,
            behaviourNotes: ["Research Mode inject"]
        )
        let (score, reasons, anomaly) = ThreatScorer.score(track: track, history: [-60, -50, -70, -45])
        track.threatScore = min(10, score + threatBoost)
        track.threatReasons = reasons
        track.anomalyScore = anomaly
        tracks[id] = track
        forensic?.record(category: "research", summary: "Synthetic track \(name)", detail: deviceClass.rawValue)
        statusText = "\(tracks.count) tracks · synthetic injected"
        return track
    }

    func clear() {
        tracks.removeAll()
        rssiHistory.removeAll()
        statusText = "Fusion cleared"
    }

    private func upsertSource(_ track: inout RFTrack, kind: RFSourceKind, label: String, confidence: Double) {
        track.sources.removeAll { $0.kind == kind && $0.label == label }
        track.sources.append(RFSourceHit(kind: kind, label: label, confidence: confidence, timestamp: Date()))
    }

    private func pruneStale(olderThan seconds: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-seconds)
        tracks = tracks.filter { $0.value.isSynthetic || $0.value.lastSeen >= cutoff }
    }

    private func estimateDistanceM(rssi: Int, txPower: Int?) -> Double {
        let tx = Double(txPower ?? -59)
        let ratio = (tx - Double(rssi)) / 20.0
        return max(0.5, pow(10.0, ratio))
    }

    private func uuidFromString(_ s: String) -> UUID {
        let digest = Array(s.utf8)
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in digest.enumerated() { bytes[i % 16] ^= b }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
