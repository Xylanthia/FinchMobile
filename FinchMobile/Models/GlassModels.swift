import Foundation

struct IoTHost: Identifiable, Codable, Hashable {
    var id: String { ip }
    var ip: String
    var mac: String?
    var vendor: String?
    var hostname: String?
    var openProbePorts: [Int]
    var services: [MDNSServiceRecord]
    var openPorts: [Int]
    var banners: [Banner]
    var fingerprint: FingerprintMatch?
    var mqttMessages: [MQTTMessage]
    var lastSeen: Date

    init(
        ip: String,
        mac: String? = nil,
        vendor: String? = nil,
        hostname: String? = nil,
        openProbePorts: [Int] = [],
        services: [MDNSServiceRecord] = [],
        openPorts: [Int] = [],
        banners: [Banner] = [],
        fingerprint: FingerprintMatch? = nil,
        mqttMessages: [MQTTMessage] = [],
        lastSeen: Date = Date()
    ) {
        self.ip = ip
        self.mac = mac
        self.vendor = vendor
        self.hostname = hostname
        self.openProbePorts = openProbePorts
        self.services = services
        self.openPorts = openPorts
        self.banners = banners
        self.fingerprint = fingerprint
        self.mqttMessages = mqttMessages
        self.lastSeen = lastSeen
    }

    var displayLabel: String {
        if let hostname, !hostname.isEmpty { return hostname }
        if let vendor, !vendor.isEmpty { return vendor }
        return ip
    }

    var hasMQTT: Bool {
        openPorts.contains(where: { [1883, 8883, 1884, 8884, 9001].contains($0) })
            || services.contains(where: { $0.type.contains("mqtt") })
    }

    mutating func merge(_ other: IoTHost) {
        if mac == nil { mac = other.mac }
        if vendor == nil { vendor = other.vendor }
        if hostname == nil || hostname?.isEmpty == true { hostname = other.hostname }
        openProbePorts = Array(Set(openProbePorts + other.openProbePorts)).sorted()
        openPorts = Array(Set(openPorts + other.openPorts)).sorted()
        var svcByKey: [String: MDNSServiceRecord] = Dictionary(
            uniqueKeysWithValues: services.map { ("\($0.type)|\($0.name)", $0) }
        )
        for s in other.services { svcByKey["\(s.type)|\(s.name)"] = s }
        services = Array(svcByKey.values).sorted { $0.name < $1.name }
        var bannerByPort: [Int: Banner] = Dictionary(uniqueKeysWithValues: banners.map { ($0.port, $0) })
        for b in other.banners { bannerByPort[b.port] = b }
        banners = bannerByPort.values.sorted { $0.port < $1.port }
        if let fp = other.fingerprint {
            if fingerprint == nil || fp.confidence > (fingerprint?.confidence ?? 0) {
                fingerprint = fp
            }
        }
        mqttMessages.append(contentsOf: other.mqttMessages)
        lastSeen = max(lastSeen, other.lastSeen)
    }
}

struct MDNSServiceRecord: Codable, Hashable, Identifiable {
    var id: String { "\(type)|\(name)|\(host):\(port)" }
    var name: String
    var type: String
    var host: String
    var port: Int
    var txt: [String: String]
}

struct Banner: Codable, Hashable, Identifiable {
    var id: String { "\(port)-\(protocolGuess)" }
    var port: Int
    var protocolGuess: String
    var rawASCII: String
    var rawHex: String
    var headers: [String: String]
}

struct FingerprintMatch: Codable, Hashable {
    var deviceType: String
    var vendor: String
    var model: String
    var confidence: Double
    var tags: [String]
    var ruleId: String
}

struct MQTTMessage: Codable, Hashable, Identifiable {
    var id: UUID
    var topic: String
    var payloadASCII: String
    var payloadHex: String
    var receivedAt: Date

    init(topic: String, payload: Data, receivedAt: Date = Date()) {
        self.id = UUID()
        self.topic = topic
        let ascii = String(data: payload.prefix(1024), encoding: .utf8)
            ?? payload.prefix(1024).map { String(format: "%02X", $0) }.joined(separator: " ")
        self.payloadASCII = ascii
        self.payloadHex = payload.prefix(1024).map { String(format: "%02X", $0) }.joined(separator: " ")
        self.receivedAt = receivedAt
    }
}

struct GlassFabricReport: Codable, Hashable {
    var query: String
    var cidr: String
    var localIP: String?
    var netmask: String?
    var startedAt: Date
    var finishedAt: Date?
    var hosts: [IoTHost]
    var warnings: [String]
    var mdnsServiceCount: Int
    var phase: String

    static func empty(query: String, cidr: String) -> GlassFabricReport {
        GlassFabricReport(
            query: query,
            cidr: cidr,
            localIP: nil,
            netmask: nil,
            startedAt: Date(),
            finishedAt: nil,
            hosts: [],
            warnings: [],
            mdnsServiceCount: 0,
            phase: "idle"
        )
    }
}

enum IoTPorts {
    /// Finch Glass ~56 surface ports
    static let surface: [Int] = [
        21, 22, 23, 25, 53, 80, 110, 111, 135, 139, 143, 443, 445, 554, 587, 631,
        993, 995, 1026, 1433, 1723, 1883, 1900, 2323, 2375, 3306, 3389, 3478, 3689,
        5000, 5353, 5432, 5683, 5800, 5900, 5985, 5986, 6379, 7001, 8000, 8080, 8443,
        8883, 8888, 9000, 9090, 9100, 9200, 9300, 10000, 11211, 27017, 37777, 47808,
        49152, 62078
    ]

    static let probeQuick: [Int] = [80, 443, 22, 1883]

    static func family(for port: Int) -> String {
        switch port {
        case 554, 8554: return "rtsp"
        case 1883, 8883, 1884, 8884, 9001: return "mqtt"
        case 22: return "ssh"
        case 23, 2323: return "telnet"
        case 80, 81, 8080, 8000, 8443, 443, 5000: return "http"
        case 37777: return "dahua"
        case 62078: return "apple-lockdown"
        case 6379: return "redis"
        case 27017: return "mongodb"
        case 11211: return "memcached"
        case 5683: return "coap"
        default: return "tcp"
        }
    }
}
