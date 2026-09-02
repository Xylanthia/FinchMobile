import Foundation

struct FingerprintRule: Codable, Hashable {
    var id: String
    var deviceType: String
    var vendor: String
    var model: String
    var confidence: Double
    var tags: [String]
    var patterns: [String]
}

final class FingerprintEngine {
    static let shared = FingerprintEngine()

    private(set) var rules: [FingerprintRule] = []

    private init() {
        loadBundled()
    }

    func loadBundled() {
        if let url = Bundle.main.url(forResource: "fingerprints", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([FingerprintRule].self, from: data) {
            rules = decoded
            return
        }
        rules = FingerprintFallback.rules
    }

    func match(banners: [Banner], services: [MDNSServiceRecord] = []) -> FingerprintMatch? {
        let corpus = (
            banners.map { "\($0.protocolGuess) \($0.rawASCII) \($0.headers.map { "\($0.key):\($0.value)" }.joined(separator: " "))" }
                + services.map { "\($0.type) \($0.name)" }
        ).joined(separator: "\n").lowercased()

        var best: FingerprintMatch?
        for rule in rules {
            var hits = 0
            for pattern in rule.patterns {
                if corpus.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    hits += 1
                }
            }
            guard hits > 0 else { continue }
            let score = rule.confidence * (Double(hits) / Double(max(rule.patterns.count, 1)))
            let candidate = FingerprintMatch(
                deviceType: rule.deviceType,
                vendor: rule.vendor,
                model: rule.model,
                confidence: min(0.99, score),
                tags: rule.tags,
                ruleId: rule.id
            )
            if candidate.confidence > (best?.confidence ?? 0) {
                best = candidate
            }
        }
        return best
    }
}

enum FingerprintFallback {
    static let rules: [FingerprintRule] = [
        FingerprintRule(id: "flock-1", deviceType: "camera", vendor: "Flock Safety", model: "ALPR / LPR", confidence: 0.96, tags: ["camera", "flock", "alpr"], patterns: ["flock.?safety", "flocksafety", "fs.?ext.?battery", "\\bflock\\b"]),
        FingerprintRule(id: "flock-2", deviceType: "camera", vendor: "Penguin", model: "Surveillance / LPR", confidence: 0.93, tags: ["camera", "alpr", "penguin"], patterns: ["\\bpenguin\\b"]),
        FingerprintRule(id: "flock-3", deviceType: "camera", vendor: "Pigvision", model: "Surveillance", confidence: 0.93, tags: ["camera", "alpr", "pigvision"], patterns: ["pigvision"]),
        FingerprintRule(id: "hik-1", deviceType: "camera", vendor: "Hikvision", model: "DVR/NVR", confidence: 0.9, tags: ["camera", "rtsp"], patterns: ["hikvision", "dvrdvs", "isapi"]),
        FingerprintRule(id: "dahua-1", deviceType: "camera", vendor: "Dahua", model: "DVR", confidence: 0.9, tags: ["camera"], patterns: ["dahua", "dh-", "webservice"]),
        FingerprintRule(id: "ha-1", deviceType: "hub", vendor: "Home Assistant", model: "Core", confidence: 0.85, tags: ["smart-home"], patterns: ["home.?assistant", "hassio"]),
        FingerprintRule(id: "mqtt-1", deviceType: "broker", vendor: "Generic", model: "MQTT", confidence: 0.7, tags: ["mqtt"], patterns: ["mqtt", "_mqtt._tcp"]),
        FingerprintRule(id: "vivint-1", deviceType: "hub", vendor: "Vivint", model: "SkyPanel / Network Module", confidence: 0.96, tags: ["vivint", "camera", "hub", "rtsp"], patterns: ["vivint", "network module", "2gig", "skypanel"]),
        FingerprintRule(id: "router-1", deviceType: "router", vendor: "Generic", model: "SOHO Router", confidence: 0.6, tags: ["network"], patterns: ["mikrotik", "ubiquiti", "openwrt", "asuswrt"]),
        FingerprintRule(id: "printer-1", deviceType: "printer", vendor: "Generic", model: "IPP/Printer", confidence: 0.75, tags: ["printer"], patterns: ["_printer._tcp", "ipp", "jetdirect"]),
        FingerprintRule(id: "apple-1", deviceType: "apple", vendor: "Apple", model: "AirPlay/Companion", confidence: 0.8, tags: ["apple"], patterns: ["_raop._tcp", "_companion-link._tcp", "airplay"]),
        FingerprintRule(id: "ssh-dropbear", deviceType: "embedded", vendor: "Generic", model: "Dropbear SSH", confidence: 0.7, tags: ["ssh"], patterns: ["dropbear"]),
        FingerprintRule(id: "openssh", deviceType: "server", vendor: "OpenSSH", model: "sshd", confidence: 0.65, tags: ["ssh"], patterns: ["openssh"]),
        FingerprintRule(id: "redis", deviceType: "database", vendor: "Redis", model: "Redis", confidence: 0.85, tags: ["db"], patterns: ["-ERR", "redis_version", "REDIS"]),
    ]
}

final class OUIDatabase {
    static let shared = OUIDatabase()
    private var map: [String: String] = [:]

    private init() {
        if let url = Bundle.main.url(forResource: "oui", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            map = decoded
        } else {
            map = OUIFallback.map
        }
    }

    func vendor(forMAC mac: String) -> String? {
        let cleaned = mac.uppercased().replacingOccurrences(of: "-", with: ":")
        let parts = cleaned.split(separator: ":")
        guard parts.count >= 3 else { return nil }
        let prefix = parts.prefix(3).joined(separator: ":")
        return map[prefix]
    }
}

enum OUIFallback {
    static let map: [String: String] = [
        "00:1A:2B": "Ayecom",
        "00:50:56": "VMware",
        "B8:27:EB": "Raspberry Pi",
        "DC:A6:32": "Raspberry Pi",
        "E4:5F:01": "Raspberry Pi",
        "00:1E:C2": "Apple",
        "AC:DE:48": "Apple",
        "F0:18:98": "Apple",
        "00:1A:11": "Google",
        "3C:5A:B4": "Google",
        "18:B4:30": "Nest",
        "64:16:66": "Nest",
        "00:17:88": "Philips Hue",
        "00:18:E7": "Vivint Smart Home",
        "84:EB:3E": "Vivint Smart Home",
        "EC:B5:FA": "Philips",
        "00:0C:29": "VMware",
        "00:15:5D": "Microsoft Hyper-V",
        "52:54:00": "QEMU/KVM",
        "00:1D:7E": "Cisco-Linksys",
        "00:25:9C": "Cisco-Linksys",
        "14:CC:20": "TP-Link",
        "50:C7:BF": "TP-Link",
        "B0:BE:76": "TP-Link",
        "A4:2B:B0": "TP-Link",
        "C8:3A:35": "Tenda",
        "00:1B:44": "SanDisk",
        "00:E0:4C": "Realtek",
        "28:6C:07": "Xiaomi",
        "64:CC:2E": "Xiaomi",
        "F8:A4:5F": "Xiaomi",
        "00:16:6C": "Samsung",
        "5C:F6:DC": "Samsung",
        "00:1A:79": "Ubiquiti",
        "24:A4:3C": "Ubiquiti",
        "FC:EC:DA": "Ubiquiti",
        "B4:FB:E4": "Ubiquiti",
        "44:D9:E7": "Ubiquiti",
        "18:E8:29": "Ubiquiti",
        "00:0D:B9": "PC Engines",
        "D8:3A:DD": "Raspberry Pi",
        "2C:CF:67": "Espressif",
        "24:0A:C4": "Espressif",
        "30:AE:A4": "Espressif",
        "84:CC:A8": "Espressif",
        "A4:CF:12": "Espressif",
        "C8:2B:96": "Espressif",
        // Flock Safety / flock-class LPR modules (from flock-back signatures)
        "58:8E:81": "Flock-class (FS Ext Battery / module)",
        "EC:1B:BD": "Flock-class Wi‑Fi module",
        "90:35:EA": "Flock-class Wi‑Fi module",
        "04:0D:84": "Flock-class Wi‑Fi module",
        "F0:82:C0": "Flock-class Wi‑Fi module",
        "1C:34:F1": "Flock-class Wi‑Fi module",
        "38:5B:44": "Flock-class Wi‑Fi module",
        "94:34:69": "Flock-class Wi‑Fi module",
        "B4:E3:F9": "Flock-class Wi‑Fi module",
        "70:C9:4E": "Flock Safety Wi‑Fi",
        "3C:91:80": "Flock Safety Wi‑Fi",
        "D8:F3:BC": "Flock Safety Wi‑Fi",
        "80:30:49": "Flock Safety Wi‑Fi",
        "14:5A:FC": "Flock Safety Wi‑Fi",
        "74:4C:A1": "Flock Safety Wi‑Fi",
        "08:3A:88": "Flock Safety Wi‑Fi",
        "9C:2F:9D": "Flock Safety Wi‑Fi",
        "94:08:53": "Flock Safety Wi‑Fi",
        "E4:AA:EA": "Flock Safety Wi‑Fi"
    ]
}

/// Passive Flock Safety / Raven / Penguin / Pigvision recognition (flock-back style).
/// iOS can match BLE names + Raven GATT UUIDs + LAN OUI/hostname — not Wi‑Fi probe sniffing.
enum FlockCameraDetector {
    struct Hit: Hashable {
        var vendor: String
        var model: String
        var confidence: String
        var reason: String
        var badge: String { "\(vendor.uppercased()) · ALPR" }
    }

    /// BLE local-name patterns (exact/contains) from flock-back.
    static let bleNameNeedles: [String] = [
        "fs ext battery",
        "flock",
        "penguin",
        "pigvision"
    ]

    /// Raven custom GATT short UUIDs (firmware 1.2.0+).
    static let ravenServiceShorts: Set<String> = [
        "3100", "3200", "3300", "3400", "3500"
    ]

    static func matchBLE(_ device: BLEDevice) -> Hit? {
        let nameBlob = [device.gattDeviceName, device.localName, device.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if nameBlob.contains("fs ext battery") {
            return Hit(
                vendor: "Flock Safety",
                model: "FS Ext Battery",
                confidence: "high",
                reason: "BLE local name matches Flock Safety Extended Battery advertisement."
            )
        }
        if nameBlob.contains("pigvision") {
            return Hit(
                vendor: "Pigvision",
                model: "Surveillance",
                confidence: "high",
                reason: "BLE local name matches Pigvision surveillance advertisement."
            )
        }
        if nameBlob.contains("penguin") {
            return Hit(
                vendor: "Penguin",
                model: "Surveillance / LPR",
                confidence: "high",
                reason: "BLE local name matches Penguin surveillance advertisement."
            )
        }
        // Whole-word Flock Safety only. "[TV] Flocka" / Samsung TVs must not match.
        if FlockCameraDetector.nameLooksLikeFlockSafety(nameBlob) {
            return Hit(
                vendor: "Flock Safety",
                model: "ALPR / LPR",
                confidence: "high",
                reason: "BLE local name matches Flock Safety advertisement."
            )
        }

        let shorts = Set(
            (device.serviceUUIDs + device.overflowServiceUUIDs + Array(device.serviceData.keys))
                .map { BLEFriendlyIdentity.normalizeUUID($0) }
        )
        let ravenHits = shorts.intersection(ravenServiceShorts)
        if ravenHits.count >= 2 {
            return Hit(
                vendor: "Raven",
                model: "LPR Camera",
                confidence: "high",
                reason: "Raven GATT services \(ravenHits.sorted().joined(separator: ", ")) — GPS/power/network/upload class."
            )
        }
        if ravenHits.count == 1 {
            return Hit(
                vendor: "Raven",
                model: "LPR Camera (possible)",
                confidence: "medium",
                reason: "Raven-class GATT service \(ravenHits.first!) advertised."
            )
        }
        return nil
    }

    static func matchHost(_ host: IoTHost) -> Hit? {
        if let mac = host.mac, let vendor = OUIDatabase.shared.vendor(forMAC: mac) {
            let lower = vendor.lowercased()
            if lower.contains("flock") {
                return Hit(
                    vendor: "Flock Safety",
                    model: "ALPR (OUI)",
                    confidence: "medium",
                    reason: "MAC OUI maps to Flock-class Wi‑Fi module (\(vendor))."
                )
            }
        }

        var parts: [String] = []
        if let hostname = host.hostname { parts.append(hostname) }
        if let vendor = host.vendor { parts.append(vendor) }
        if let fp = host.fingerprint {
            parts.append(fp.vendor)
            parts.append(fp.model)
            parts.append(fp.deviceType)
            parts.append(contentsOf: fp.tags)
        }
        for banner in host.banners {
            parts.append(banner.rawASCII)
        }
        for svc in host.services {
            parts.append(svc.name)
            parts.append(svc.type)
        }
        let blob = parts.joined(separator: " ").lowercased()

        if blob.contains("pigvision") || blob.contains("pig vision") {
            return Hit(vendor: "Pigvision", model: "Surveillance", confidence: "high", reason: "Hostname/banner matched Pigvision.")
        }
        if blob.contains(" penguin") || blob.hasPrefix("penguin") || blob.contains("penguin ") {
            return Hit(vendor: "Penguin", model: "Surveillance / LPR", confidence: "high", reason: "Hostname/banner matched Penguin.")
        }
        if blob.contains("flock safety") || blob.contains("flocksafety") || blob.contains("fs ext battery")
            || FlockCameraDetector.nameLooksLikeFlockSafety(blob) {
            return Hit(vendor: "Flock Safety", model: "ALPR / LPR", confidence: "high", reason: "Hostname/banner matched Flock Safety.")
        }
        if blob.contains("raven") && (blob.contains("lpr") || blob.contains("camera") || blob.contains("alpr")) {
            return Hit(vendor: "Raven", model: "LPR Camera", confidence: "medium", reason: "Hostname/banner matched Raven LPR.")
        }

        if let tags = host.fingerprint?.tags {
            let hitTag = tags.contains { tag in
                let t = tag.lowercased()
                return t.contains("flock") || t == "alpr"
            }
            if hitTag {
                let vendor = host.fingerprint?.vendor ?? "Flock Safety"
                return Hit(
                    vendor: vendor,
                    model: host.fingerprint?.model ?? "ALPR / LPR",
                    confidence: "high",
                    reason: "Glass fingerprint tagged ALPR / Flock-class."
                )
            }
        }
        return nil
    }

    /// True only for Flock Safety-style names, not nicknames like Flocka or "[TV] …".
    static func nameLooksLikeFlockSafety(_ raw: String) -> Bool {
        let t = raw.lowercased()
        if t.contains("[tv]") { return false }
        if t.contains("samsung") && t.contains("tv") { return false }
        if t.contains("flock safety") || t.contains("flocksafety") || t.contains("fs ext battery") {
            return true
        }
        guard let regex = try? NSRegularExpression(pattern: #"\bflock\b"#) else { return false }
        let range = NSRange(t.startIndex..<t.endIndex, in: t)
        return regex.firstMatch(in: t, range: range) != nil
    }

    static func isFlockClass(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.contains("[tv]") { return false }
        if nameLooksLikeFlockSafety(t) { return true }
        if t.contains("penguin") || t.contains("pigvision") { return true }
        if t.contains("fs ext battery") { return true }
        if t.contains("alpr") && !t.contains("[tv]") { return true }
        if t.contains("raven") && (t.contains("lpr") || t.contains("alpr")) { return true }
        return false
    }
}

enum PhoneDetector {
    struct Hit {
        var title: String
        var reason: String
        var confidence: String
    }

    static func nameBlob(_ device: BLEDevice) -> String {
        [device.gattDeviceName, device.localName, device.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
    }

    static func isAudioAccessory(_ t: String) -> Bool {
        t.contains("buds") || t.contains("airpods") || t.contains("earbud") || t.contains("headset")
            || t.contains("headphone") || t.contains("beats") || t.contains("freebuds")
    }

    static func isWatch(_ t: String) -> Bool {
        t.contains("watch") || t.contains("galaxy watch") || t.contains("apple watch") || t.contains("pixel watch")
    }

    static func matchBLE(_ device: BLEDevice) -> Hit? {
        let t = nameBlob(device)
        if isAudioAccessory(t) || isWatch(t) { return nil }

        if t.contains("iphone") {
            return Hit(title: device.broadcastName ?? "iPhone", reason: "Broadcast name contains iPhone.", confidence: "high")
        }
        if t.contains("ipad") {
            return Hit(title: device.broadcastName ?? "iPad", reason: "Broadcast name contains iPad.", confidence: "high")
        }
        if BLEFriendlyIdentity.matches(t, ["pixel fold", "pixel tablet", "pixel 6", "pixel 7", "pixel 8", "pixel 9"])
            || (t.contains("pixel") && !t.contains("buds") && !t.contains("watch") && !t.contains("stand")) {
            if t.contains("pixel") {
                return Hit(title: device.broadcastName ?? "Pixel phone", reason: "Broadcast name looks like a Pixel phone, not buds/watch.", confidence: "high")
            }
        }
        if t.contains("galaxy s") || t.contains("galaxy z") || t.contains("galaxy note") || t.contains("galaxy fold")
            || t.contains("galaxy tab") || t.contains("galaxy a") || t.hasPrefix("sm-") || t.contains(" sm-") {
            return Hit(title: device.broadcastName ?? "Galaxy phone/tablet", reason: "Samsung Galaxy phone/tablet name pattern.", confidence: "high")
        }
        if BLEFriendlyIdentity.matches(t, ["oneplus", "nothing phone", "motorola", "moto g", "moto razr", "redmi note", "poco ", "oppo ", "vivo ", "realme", "honor magic", "sony xperia"]) {
            return Hit(title: device.broadcastName ?? "Android phone", reason: "Broadcast name matches a phone OEM model pattern.", confidence: "high")
        }

        if device.manufacturerCompanyId == 0x004C {
            let payload = BLEValueExplainer.parseHex(device.manufacturerDataHex ?? "")
            if payload.first == 0x10 {
                return Hit(title: device.broadcastName ?? "iPhone / iPad (Nearby Info)", reason: "Apple Continuity type 0x10 Nearby Info — phone/tablet, not AirTag/AirPods.", confidence: "high")
            }
            if payload.first == 0x0D || payload.first == 0x0E {
                return Hit(title: device.broadcastName ?? "iPhone Instant Hotspot", reason: "Apple Instant Hotspot Continuity — typically an iPhone.", confidence: "medium")
            }
            if payload.first == 0x05 {
                return Hit(title: device.broadcastName ?? "iPhone AirDrop", reason: "Apple AirDrop Continuity — typically iPhone/iPad.", confidence: "medium")
            }
        }

        let shorts = Set(
            (device.serviceUUIDs + device.overflowServiceUUIDs + Array(device.serviceData.keys))
                .map { BLEFriendlyIdentity.normalizeUUID($0) }
        )
        if shorts.contains("FD6F") {
            return Hit(title: device.broadcastName ?? "Phone (Exposure Notification)", reason: "Service FD6F Exposure Notification — almost always a phone OS.", confidence: "medium")
        }
        return nil
    }
}

enum BeaconDetector {
    static func matchBLE(_ device: BLEDevice) -> Bool {
        let shorts = Set(
            (device.serviceUUIDs + device.overflowServiceUUIDs + Array(device.serviceData.keys))
                .map { BLEFriendlyIdentity.normalizeUUID($0) }
        )
        if shorts.contains("FEAA") { return true }
        if device.manufacturerCompanyId == 0x004C {
            let payload = BLEValueExplainer.parseHex(device.manufacturerDataHex ?? "")
            if payload.first == 0x02, payload.count >= 21 { return true }
        }
        if let name = device.broadcastName?.lowercased(), name.contains("ibeacon") || name.contains("eddystone") || name.contains("estimote") {
            return true
        }
        return false
    }
}

enum ComputerDetector {
    static func matchBLE(_ device: BLEDevice) -> Bool {
        let t = [device.gattDeviceName, device.localName, device.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if BLEFriendlyIdentity.matches(t, ["macbook", "imac", "mac mini", "mac studio", "mac pro", "thinkpad", "latitude", "surface laptop", "surface pro", "windows"]) {
            return true
        }
        if device.manufacturerCompanyId == 0x0006 {
            let payload = BLEValueExplainer.parseHex(device.manufacturerDataHex ?? "")
            if payload.first == 0x01 { return true }
        }
        if device.manufacturerCompanyId == 0x004C {
            let payload = BLEValueExplainer.parseHex(device.manufacturerDataHex ?? "")
            if payload.first == 0x0C, t.contains("mac") { return true }
        }
        return false
    }
}

enum GamingDetector {
    static func matchBLE(_ device: BLEDevice) -> Bool {
        let t = [device.gattDeviceName, device.localName, device.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return BLEFriendlyIdentity.matches(t, [
            "dualsense", "dualshock", "wireless controller", "xbox", "joy-con", "joycon",
            "nintendo", "pro controller", "stadia", "steam deck", "dualsense edge"
        ])
    }
}

enum AutomotiveDetector {
    struct Hit {
        var title: String
        var reason: String
        var confidence: String
    }

    static func blob(_ device: BLEDevice) -> String {
        [device.gattDeviceName, device.localName, device.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
    }

    static func matchBLE(_ device: BLEDevice) -> Hit? {
        let t = blob(device)

        if BLEFriendlyIdentity.matches(t, [
            "jeep", "uconnect", "wrangler", "gladiator", "cherokee", "grand cherokee",
            "wagoneer", "compass", "renegade", "gladiator", "ram 1500", "ram 2500", "ram 3500",
            "dodge", "chrysler", "stellantis"
        ]) {
            return Hit(
                title: device.broadcastName ?? "Stellantis / Jeep / Uconnect",
                reason: "Name matches Jeep / Uconnect / RAM / Dodge / Chrysler.",
                confidence: "high"
            )
        }

        if BLEFriendlyIdentity.matches(t, [
            "tesla", "carplay", "android auto", "onstar", "sync ", "fordpass", "bluelink",
            "uvo ", "hyundai", "kia ", "bmw", "mini cooper", "mercedes", "mbux", "audi ",
            "vw ", "carnet", "car-net", "hondalink", "toyota", "lexus", "subaru", "mazda",
            "gm ", "chevrolet", "silverado", "gmc ", "cadillac", "nissan", "infiniti",
            "volvo", "polestar", "rivian", "lucid", "cybertruck"
        ]) {
            return Hit(
                title: device.broadcastName ?? "Vehicle Bluetooth",
                reason: "Broadcast name matches a vehicle / infotainment brand.",
                confidence: "high"
            )
        }

        if BLEFriendlyIdentity.matches(t, [
            "obd", "elm327", "veepeak", "vgate", "viecar", "carista", "nonda", "bafx",
            "konnwei", "obdlink", "fixd", "torque"
        ]) {
            return Hit(
                title: device.broadcastName ?? "OBD / car dongle",
                reason: "BLE OBD adapter name — car diagnostic dongle, not the radio.",
                confidence: "high"
            )
        }

        if device.manufacturerCompanyId == 0x0A7C {
            return Hit(title: "TPMS sensor", reason: "Bluetooth company ID 0x0A7C (TPMS).", confidence: "high")
        }
        if device.manufacturerCompanyId == 0x0175 {
            return Hit(
                title: device.broadcastName ?? "Tesla-company BLE",
                reason: "Tesla Bluetooth company ID 0x0175. Could be the car or a Tesla accessory.",
                confidence: "medium"
            )
        }
        return nil
    }
}
