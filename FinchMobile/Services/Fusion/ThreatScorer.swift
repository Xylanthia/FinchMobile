import Foundation

enum ThreatScorer {
    static func score(track: RFTrack, history: [Int]) -> (Int, [String], Double) {
        var score = 1
        var reasons: [String] = []
        var anomaly = 0.0

        switch track.deviceClass {
        case .flipper:
            score += 4; reasons.append("Flipper Zero signature")
        case .hackrf:
            score += 5; reasons.append("SDR / HackRF class signature")
        case .drone:
            score += 3; reasons.append("Drone RF / Remote ID class")
        case .droneController:
            score += 3; reasons.append("Likely drone controller")
        case .airtag:
            score += 1; reasons.append("Tracker beacon (AirTag-class)")
        default: break
        }

        if let rssi = track.rssi, rssi > -45 {
            score += 1
            reasons.append("Very close proximity (RSSI \(rssi))")
        }

        if history.count >= 4 {
            let mean = Double(history.reduce(0, +)) / Double(history.count)
            let variance = history.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(history.count)
            let std = sqrt(variance)
            if std > 12 {
                anomaly = min(1.0, std / 30.0)
                score += 1
                reasons.append(String(format: "RSSI volatility σ=%.1f", std))
            }
        }

        if track.sources.contains(where: { $0.kind == .synthetic }) {
            reasons.append("Synthetic / research inject")
        }

        if let meta = track.droneMeta {
            if meta.mavlinkPortOpen {
                score += 2
                reasons.append("Open MAVLink TCP surface")
            }
            if meta.controllerNearby && track.deviceClass == .drone {
                score += 1
                reasons.append("Controller + airframe correlation")
            }
        }

        let nameBlob = [
            track.displayName,
            track.deviceClass.rawValue,
            track.threatReasons.joined(separator: " "),
            track.linkedHostIP ?? ""
        ].joined(separator: " ").lowercased()
        if FlockCameraDetector.isFlockClass(nameBlob) || track.deviceClass == .camera && nameBlob.contains("alpr") {
            score += 2
            reasons.append("Flock-class / ALPR security camera signature")
        }

        score = min(10, max(1, score))
        return (score, reasons, anomaly)
    }

    static func classifyBLE(_ device: BLEDevice) -> RFDeviceClass {
        if FlockCameraDetector.matchBLE(device) != nil { return .camera }

        let cat = (device.friendly.deviceType + " " + device.friendly.category).lowercased()
        let blob = [
            device.displayName,
            device.manufacturerName ?? "",
            device.friendly.title,
            device.friendly.summary,
            cat,
            device.serviceUUIDs.joined(separator: " ")
        ].joined(separator: " ").lowercased()

        if blob.contains("flipper") { return .flipper }
        if blob.contains("hackrf") || blob.contains("rtl-sdr") || blob.contains("rtlsdr") { return .hackrf }
        if blob.contains("airtag") || blob.contains("find my") || cat.contains("tracker") {
            return .airtag
        }
        if blob.contains("dji") || blob.contains("mavic") || blob.contains("autel")
            || blob.contains("skydio") || blob.contains("parrot") || blob.contains("drone") {
            return .drone
        }
        if blob.contains("controller") && (blob.contains("rc") || blob.contains("drone")) {
            return .droneController
        }
        if blob.contains("tpms") || cat.contains("tpms") || cat.contains("car") { return .vehicleTPMS }
        if cat.contains("phone") { return .phone }
        if cat.contains("computer") || blob.contains("macbook") { return .laptop }
        if cat.contains("camera") || blob.contains("camera") || cat.contains("alpr") { return .camera }
        if cat.contains("sensor") || cat.contains("smart") { return .iot }
        return .unknown
    }

    static func classifyHost(_ host: IoTHost) -> RFDeviceClass {
        if FlockCameraDetector.matchHost(host) != nil { return .camera }
        let tags = host.fingerprint?.tags ?? []
        let fp = [host.fingerprint?.deviceType, host.fingerprint?.vendor, host.fingerprint?.model]
            .compactMap { $0 }
        let blob = ([host.hostname ?? "", host.vendor ?? ""] + tags + fp)
            .joined(separator: " ").lowercased()
        if blob.contains("mavlink") || host.openPorts.contains(where: { (5760...5763).contains($0) }) {
            return .drone
        }
        if blob.contains("camera") || blob.contains("rtsp") || blob.contains("onvif")
            || blob.contains("flock") || blob.contains("alpr") || blob.contains("lpr") {
            return .camera
        }
        if blob.contains("drone") || blob.contains("dji") { return .drone }
        return .iot
    }
}
