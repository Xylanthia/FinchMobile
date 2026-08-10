import Foundation

struct OffenseHit: Identifiable, Codable, Hashable {
    var id: String { "\(source)|\(port)|\(summary)" }
    var source: String
    var severity: String
    var port: Int
    var proto: String
    var summary: String
    var detail: String
}

struct IoTHost: Identifiable, Codable, Hashable {
    var id: String { ip }
    var ip: String
    var mac: String?
    var vendor: String?
    var hostname: String?
    var openProbePorts: [Int]
    var services: [MDNSServiceRecord]
    var openPorts: [Int]
    var openUDPPorts: [Int]
    var banners: [Banner]
    var fingerprint: FingerprintMatch?
    var mqttMessages: [MQTTMessage]
    var offenseHits: [OffenseHit]
    var lastSeen: Date

    init(
        ip: String,
        mac: String? = nil,
        vendor: String? = nil,
        hostname: String? = nil,
        openProbePorts: [Int] = [],
        services: [MDNSServiceRecord] = [],
        openPorts: [Int] = [],
        openUDPPorts: [Int] = [],
        banners: [Banner] = [],
        fingerprint: FingerprintMatch? = nil,
        mqttMessages: [MQTTMessage] = [],
        offenseHits: [OffenseHit] = [],
        lastSeen: Date = Date()
    ) {
        self.ip = ip
        self.mac = mac
        self.vendor = vendor
        self.hostname = hostname
        self.openProbePorts = openProbePorts
        self.services = services
        self.openPorts = openPorts
        self.openUDPPorts = openUDPPorts
        self.banners = banners
        self.fingerprint = fingerprint
        self.mqttMessages = mqttMessages
        self.offenseHits = offenseHits
        self.lastSeen = lastSeen
    }

    enum CodingKeys: String, CodingKey {
        case ip, mac, vendor, hostname, openProbePorts, services, openPorts, openUDPPorts
        case banners, fingerprint, mqttMessages, offenseHits, lastSeen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ip = try c.decode(String.self, forKey: .ip)
        mac = try c.decodeIfPresent(String.self, forKey: .mac)
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor)
        hostname = try c.decodeIfPresent(String.self, forKey: .hostname)
        openProbePorts = try c.decodeIfPresent([Int].self, forKey: .openProbePorts) ?? []
        services = try c.decodeIfPresent([MDNSServiceRecord].self, forKey: .services) ?? []
        openPorts = try c.decodeIfPresent([Int].self, forKey: .openPorts) ?? []
        openUDPPorts = try c.decodeIfPresent([Int].self, forKey: .openUDPPorts) ?? []
        banners = try c.decodeIfPresent([Banner].self, forKey: .banners) ?? []
        fingerprint = try c.decodeIfPresent(FingerprintMatch.self, forKey: .fingerprint)
        mqttMessages = try c.decodeIfPresent([MQTTMessage].self, forKey: .mqttMessages) ?? []
        offenseHits = try c.decodeIfPresent([OffenseHit].self, forKey: .offenseHits) ?? []
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? Date()
    }

    var displayLabel: String {
        if let hostname, !hostname.isEmpty { return hostname }
        if let vendor, !vendor.isEmpty { return vendor }
        return ip
    }

    var hasMQTT: Bool {
        openPorts.contains(where: { IoTPorts.mqtt.contains($0) })
            || services.contains(where: { $0.type.contains("mqtt") })
    }

    var mqttPorts: [Int] {
        openPorts.filter { IoTPorts.mqtt.contains($0) }
    }

    mutating func merge(_ other: IoTHost) {
        if mac == nil { mac = other.mac }
        if vendor == nil { vendor = other.vendor }
        if hostname == nil || hostname?.isEmpty == true { hostname = other.hostname }
        openProbePorts = Array(Set(openProbePorts + other.openProbePorts)).sorted()
        openPorts = Array(Set(openPorts + other.openPorts)).sorted()
        openUDPPorts = Array(Set(openUDPPorts + other.openUDPPorts)).sorted()
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
        var hitKeys = Set(offenseHits.map(\.id))
        for hit in other.offenseHits where !hitKeys.contains(hit.id) {
            offenseHits.append(hit)
            hitKeys.insert(hit.id)
        }
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
    var ssdpDeviceCount: Int
    var phase: String

    enum CodingKeys: String, CodingKey {
        case query, cidr, localIP, netmask, startedAt, finishedAt, hosts, warnings
        case mdnsServiceCount, ssdpDeviceCount, phase
    }

    init(
        query: String,
        cidr: String,
        localIP: String?,
        netmask: String?,
        startedAt: Date,
        finishedAt: Date?,
        hosts: [IoTHost],
        warnings: [String],
        mdnsServiceCount: Int,
        ssdpDeviceCount: Int,
        phase: String
    ) {
        self.query = query
        self.cidr = cidr
        self.localIP = localIP
        self.netmask = netmask
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.hosts = hosts
        self.warnings = warnings
        self.mdnsServiceCount = mdnsServiceCount
        self.ssdpDeviceCount = ssdpDeviceCount
        self.phase = phase
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decode(String.self, forKey: .query)
        cidr = try c.decode(String.self, forKey: .cidr)
        localIP = try c.decodeIfPresent(String.self, forKey: .localIP)
        netmask = try c.decodeIfPresent(String.self, forKey: .netmask)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        hosts = try c.decodeIfPresent([IoTHost].self, forKey: .hosts) ?? []
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        mdnsServiceCount = try c.decodeIfPresent(Int.self, forKey: .mdnsServiceCount) ?? 0
        ssdpDeviceCount = try c.decodeIfPresent(Int.self, forKey: .ssdpDeviceCount) ?? 0
        phase = try c.decodeIfPresent(String.self, forKey: .phase) ?? "idle"
    }

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
            ssdpDeviceCount: 0,
            phase: "idle"
        )
    }
}

enum IoTPorts {
    /// Aligned with Finch Glass fabric_ports FABRIC_SURFACE_PORTS (+ common extras)
    static let surface: [Int] = [
        21, 22, 23, 25, 53, 80, 81, 110, 111, 135, 139, 143, 443, 445, 554, 587, 631,
        993, 995, 1026, 1032, 1433, 1723, 1880, 1883, 1884, 1900, 2323, 2375, 3306, 3389,
        3478, 3689, 5000, 5353, 5432, 5555, 5683, 5760, 5761, 5762, 5763, 5800, 5900,
        5985, 5986, 6379, 7001, 7070, 7547, 8000, 8001, 8080, 8081, 8123, 8443, 8554,
        8883, 8884, 8888, 9000, 9001, 9090, 9100, 9200, 9300, 9999, 10000, 10554,
        11211, 27017, 34567, 37777, 47808, 49152, 62078
    ]

    static let probeQuick: [Int] = [80, 443, 22, 1883, 554]

    static let mqtt: Set<Int> = [1883, 8883, 1884, 8884, 9001]
    static let http: Set<Int> = [80, 81, 443, 8000, 8001, 8080, 8081, 8443, 5000, 9000, 9001, 8123, 1880, 9200]
    static let rtsp: Set<Int> = [554, 8554, 1032, 7070, 10554]
    static let udpSurface: [Int] = [
        69, 123, 161, 162, 1900, 3702, 5353, 5683, 5684,
        14540, 14550, 14551, 14552, 14553, 14555, 14560, 14580, 18570, 47808
    ]

    static func family(for port: Int) -> String {
        switch port {
        case 554, 8554, 1032, 7070, 10554: return "rtsp"
        case 1883, 8883, 1884, 8884, 9001: return "mqtt"
        case 22: return "ssh"
        case 23, 2323: return "telnet"
        case 21: return "ftp"
        case 80, 81, 8080, 8000, 8001, 8443, 443, 5000, 8081: return "http"
        case 8123: return "home-assistant"
        case 1880: return "nodered"
        case 5555: return "adb"
        case 37777: return "dahua"
        case 34567: return "hikvision-dvr"
        case 7547: return "tr069"
        case 62078: return "apple-lockdown"
        case 6379: return "redis"
        case 27017: return "mongodb"
        case 11211: return "memcached"
        case 9200: return "elasticsearch"
        case 5683, 5684: return "coap"
        case 5760, 5761, 5762, 5763: return "drone"
        default: return "tcp"
        }
    }

    static func udpFamily(for port: Int) -> String {
        switch port {
        case 69: return "tftp"
        case 123: return "ntp"
        case 161: return "snmp"
        case 162: return "snmp-trap"
        case 1900: return "ssdp"
        case 3702: return "ws-discovery"
        case 5353: return "mdns"
        case 5683: return "coap"
        case 5684: return "coaps"
        case 14540, 14550, 14551, 14552, 14553, 14555, 14560, 14580, 18570: return "mavlink"
        case 47808: return "bacnet"
        default: return "udp"
        }
    }
}
