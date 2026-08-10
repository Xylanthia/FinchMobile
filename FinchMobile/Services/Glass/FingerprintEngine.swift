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
        FingerprintRule(id: "hik-1", deviceType: "camera", vendor: "Hikvision", model: "DVR/NVR", confidence: 0.9, tags: ["camera", "rtsp"], patterns: ["hikvision", "dvrdvs", "isapi"]),
        FingerprintRule(id: "dahua-1", deviceType: "camera", vendor: "Dahua", model: "DVR", confidence: 0.9, tags: ["camera"], patterns: ["dahua", "dh-", "webservice"]),
        FingerprintRule(id: "ha-1", deviceType: "hub", vendor: "Home Assistant", model: "Core", confidence: 0.85, tags: ["smart-home"], patterns: ["home.?assistant", "hassio"]),
        FingerprintRule(id: "mqtt-1", deviceType: "broker", vendor: "Generic", model: "MQTT", confidence: 0.7, tags: ["mqtt"], patterns: ["mqtt", "_mqtt._tcp"]),
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
        "C8:2B:96": "Espressif"
    ]
}
