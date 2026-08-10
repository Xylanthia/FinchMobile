import Foundation
import Network

/// Authorized LAN offense probes — anonymous / banner / discovery only (no credential stuffing).
final class OffenseProbeService {
    var onProgress: ((String) -> Void)?

    func probeHost(ip: String, openTCP: [Int], banners: [Banner]) async -> (hits: [OffenseHit], openUDP: [Int]) {
        var hits: [OffenseHit] = []
        let bannerByPort = Dictionary(uniqueKeysWithValues: banners.map { ($0.port, $0) })

        onProgress?("Offense TCP \(ip)…")
        for port in openTCP {
            hits.append(contentsOf: await probeTCP(ip: ip, port: port, banner: bannerByPort[port]))
        }

        onProgress?("Offense UDP \(ip)…")
        let udpOpen = await scanUDP(ip: ip, ports: IoTPorts.udpSurface)
        for port in udpOpen {
            let fam = IoTPorts.udpFamily(for: port)
            hits.append(
                OffenseHit(
                    source: "offense.udp",
                    severity: ["snmp", "coap", "mavlink", "tftp"].contains(fam) ? "HIGH" : "MEDIUM",
                    port: port,
                    proto: "udp",
                    summary: "Open UDP \(fam) · \(ip):\(port)",
                    detail: "UDP elicit response on \(fam)"
                )
            )
            if port == 161 {
                if let snmp = await probeSNMP(ip: ip) {
                    hits.append(snmp)
                }
            }
            if port == 5683 || port == 5684 {
                if let coap = await probeCoAP(ip: ip, port: port) {
                    hits.append(coap)
                }
            }
        }

        return (hits, udpOpen)
    }

    private func probeTCP(ip: String, port: Int, banner: Banner?) async -> [OffenseHit] {
        var hits: [OffenseHit] = []
        let family = IoTPorts.family(for: port)

        hits.append(
            OffenseHit(
                source: "offense.ports",
                severity: severityFor(family: family, port: port),
                port: port,
                proto: "tcp",
                summary: "Open \(family) · \(ip):\(port)",
                detail: banner?.rawASCII.prefix(240).description ?? "tcp connect open"
            )
        )

        switch family {
        case "http", "home-assistant", "nodered", "elasticsearch":
            hits.append(contentsOf: await probeHTTP(ip: ip, port: port, tls: port == 443 || port == 8443))
            if let onvif = await probeONVIF(ip: ip, port: port) {
                hits.append(onvif)
            }
        case "rtsp", "dahua", "hikvision-dvr":
            if let b = banner, !b.rawASCII.isEmpty {
                hits.append(
                    OffenseHit(
                        source: "offense.rtsp",
                        severity: "HIGH",
                        port: port,
                        proto: "tcp",
                        summary: "RTSP/video surface · \(ip):\(port)",
                        detail: String(b.rawASCII.prefix(300))
                    )
                )
            }
        case "telnet":
            hits.append(
                OffenseHit(
                    source: "offense.telnet",
                    severity: "HIGH",
                    port: port,
                    proto: "tcp",
                    summary: "Telnet exposed · \(ip):\(port)",
                    detail: banner?.rawASCII.prefix(200).description ?? "cleartext remote shell surface"
                )
            )
        case "ftp":
            hits.append(contentsOf: await probeFTP(ip: ip, port: port, banner: banner))
        case "redis":
            if let hit = await probeRedis(ip: ip, port: port) { hits.append(hit) }
        case "memcached":
            if let hit = await probeMemcached(ip: ip, port: port) { hits.append(hit) }
        case "mongodb":
            hits.append(
                OffenseHit(
                    source: "offense.mongodb",
                    severity: "HIGH",
                    port: port,
                    proto: "tcp",
                    summary: "MongoDB port open · \(ip):\(port)",
                    detail: "Anonymous auth not verified — port exposed on LAN"
                )
            )
        case "adb":
            hits.append(
                OffenseHit(
                    source: "offense.ports",
                    severity: "HIGH",
                    port: port,
                    proto: "tcp",
                    summary: "ADB debug port · \(ip):\(port)",
                    detail: "Android Debug Bridge surface"
                )
            )
        case "mqtt":
            hits.append(
                OffenseHit(
                    source: "offense.mqtt",
                    severity: "HIGH",
                    port: port,
                    proto: "tcp",
                    summary: "MQTT broker · \(ip):\(port)",
                    detail: banner?.rawHex.prefix(80).description ?? "MQTT CONNECT probe surface"
                )
            )
        default:
            break
        }
        return hits
    }

    private func severityFor(family: String, port: Int) -> String {
        if ["mqtt", "rtsp", "telnet", "adb", "dahua", "hikvision-dvr", "tr069", "drone"].contains(family)
            || [23, 21, 5555, 7547].contains(port) {
            return "HIGH"
        }
        return "MEDIUM"
    }

    private func probeHTTP(ip: String, port: Int, tls: Bool) async -> [OffenseHit] {
        // Network.framework TLS to arbitrary hosts needs NWProtocolTLS; keep plaintext HTTP for common ports.
        // For 443/8443 we still try plaintext first as many IoT TLS stacks speak HTTP unexpectedly; skip TLS complexity.
        _ = tls
        var hits: [OffenseHit] = []
        let paths = ["/", "/admin", "/login", "/cgi-bin/", "/onvif/device_service"]
        for path in paths.prefix(3) {
            let req = "GET \(path) HTTP/1.0\r\nHost: \(ip)\r\nUser-Agent: FinchMobile/1.1\r\nConnection: close\r\nAccept: */*\r\n\r\n"
            guard let data = await TCPProbe.connectAndIO(
                host: ip,
                port: UInt16(port),
                timeout: 2.2,
                send: Data(req.utf8),
                readLimit: 4096
            ), !data.isEmpty else { continue }
            let ascii = String(decoding: data, as: UTF8.self)
            let status = ascii.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let server = headerValue(ascii, key: "Server")
            let title = extractTitle(ascii)
            hits.append(
                OffenseHit(
                    source: "offense.http",
                    severity: path != "/" ? "MEDIUM" : "INFO",
                    port: port,
                    proto: "tcp",
                    summary: "HTTP \(path) · \(status)",
                    detail: [server.map { "Server: \($0)" }, title.map { "Title: \($0)" }]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                        + " · " + String(ascii.prefix(180))
                )
            )
            break
        }
        return hits
    }

    private func probeONVIF(ip: String, port: Int) async -> OffenseHit? {
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>\
        <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">\
        <s:Body><GetDeviceInformation xmlns="http://www.onvif.org/ver10/device/wsdl"/></s:Body>\
        </s:Envelope>
        """
        let req = """
        POST /onvif/device_service HTTP/1.0\r
        Host: \(ip)\r
        User-Agent: FinchMobile/1.1\r
        Content-Type: application/soap+xml; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        guard let data = await TCPProbe.connectAndIO(
            host: ip,
            port: UInt16(port),
            timeout: 2.5,
            send: Data(req.utf8),
            readLimit: 4096
        ), !data.isEmpty else { return nil }
        let ascii = String(decoding: data, as: UTF8.self).lowercased()
        guard ascii.contains("onvif") || ascii.contains("deviceinformation") || ascii.contains("soap") else {
            return nil
        }
        return OffenseHit(
            source: "offense.onvif",
            severity: "HIGH",
            port: port,
            proto: "tcp",
            summary: "ONVIF-ish response · \(ip):\(port)",
            detail: String(String(decoding: data, as: UTF8.self).prefix(280))
        )
    }

    private func probeFTP(ip: String, port: Int, banner: Banner?) async -> [OffenseHit] {
        var hits: [OffenseHit] = [
            OffenseHit(
                source: "offense.ftp",
                severity: "MEDIUM",
                port: port,
                proto: "tcp",
                summary: "FTP banner · \(ip):\(port)",
                detail: banner?.rawASCII.prefix(200).description ?? "ftp open"
            )
        ]
        // Anonymous probe: USER anonymous / PASS finch@
        let script = "USER anonymous\r\nPASS finch@\r\nQUIT\r\n"
        if let data = await TCPProbe.connectAndIO(
            host: ip,
            port: UInt16(port),
            timeout: 3.0,
            send: Data(script.utf8),
            readLimit: 2048
        ) {
            let ascii = String(decoding: data, as: UTF8.self)
            if ascii.contains("230") {
                hits.append(
                    OffenseHit(
                        source: "offense.ftp",
                        severity: "HIGH",
                        port: port,
                        proto: "tcp",
                        summary: "FTP anonymous login accepted · \(ip):\(port)",
                        detail: String(ascii.prefix(240))
                    )
                )
            }
        }
        return hits
    }

    private func probeRedis(ip: String, port: Int) async -> OffenseHit? {
        let payload = Data("INFO\r\nQUIT\r\n".utf8)
        guard let data = await TCPProbe.connectAndIO(
            host: ip, port: UInt16(port), timeout: 2.0, send: payload, readLimit: 2048
        ), !data.isEmpty else { return nil }
        let ascii = String(decoding: data, as: UTF8.self)
        if ascii.contains("redis_version") || ascii.hasPrefix("$") || ascii.contains("# Server") {
            return OffenseHit(
                source: "offense.redis",
                severity: "HIGH",
                port: port,
                proto: "tcp",
                summary: "Redis INFO without auth · \(ip):\(port)",
                detail: String(ascii.prefix(240))
            )
        }
        if ascii.lowercased().contains("auth") || ascii.contains("-NOAUTH") {
            return OffenseHit(
                source: "offense.redis",
                severity: "MEDIUM",
                port: port,
                proto: "tcp",
                summary: "Redis requires AUTH · \(ip):\(port)",
                detail: String(ascii.prefix(160))
            )
        }
        return nil
    }

    private func probeMemcached(ip: String, port: Int) async -> OffenseHit? {
        let payload = Data("stats\r\nquit\r\n".utf8)
        guard let data = await TCPProbe.connectAndIO(
            host: ip, port: UInt16(port), timeout: 2.0, send: payload, readLimit: 2048
        ), !data.isEmpty else { return nil }
        let ascii = String(decoding: data, as: UTF8.self)
        guard ascii.contains("STAT") else { return nil }
        return OffenseHit(
            source: "offense.memcached",
            severity: "HIGH",
            port: port,
            proto: "tcp",
            summary: "Memcached stats open · \(ip):\(port)",
            detail: String(ascii.prefix(200))
        )
    }

    private func scanUDP(ip: String, ports: [Int]) async -> [Int] {
        var open: [Int] = []
        await withTaskGroup(of: (Int, Bool).self) { group in
            for port in ports {
                group.addTask {
                    let ok = await UDPProbe.elicit(host: ip, port: UInt16(port), payload: UDPProbe.payload(for: port), timeout: 1.0)
                    return (port, ok)
                }
            }
            for await (port, ok) in group where ok {
                open.append(port)
            }
        }
        return open.sorted()
    }

    private func probeSNMP(ip: String) async -> OffenseHit? {
        let payload = UDPProbe.snmpGetPublicSysDescr()
        guard let data = await UDPProbe.exchange(host: ip, port: 161, payload: payload, timeout: 1.5),
              !data.isEmpty else { return nil }
        return OffenseHit(
            source: "offense.snmp",
            severity: "HIGH",
            port: 161,
            proto: "udp",
            summary: "SNMP public community responded · \(ip)",
            detail: data.map { String(format: "%02X", $0) }.joined(separator: " ").prefix(160).description
        )
    }

    private func probeCoAP(ip: String, port: Int) async -> OffenseHit? {
        let payload = UDPProbe.coapWellKnownCore()
        guard let data = await UDPProbe.exchange(host: ip, port: UInt16(port), payload: payload, timeout: 1.5),
              !data.isEmpty else { return nil }
        let ascii = String(decoding: data, as: UTF8.self)
        return OffenseHit(
            source: "offense.coap",
            severity: "HIGH",
            port: port,
            proto: "udp",
            summary: "CoAP response · \(ip):\(port)",
            detail: ascii.isEmpty
                ? data.map { String(format: "%02X", $0) }.joined(separator: " ").prefix(120).description
                : String(ascii.prefix(200))
        )
    }

    private func headerValue(_ ascii: String, key: String) -> String? {
        for line in ascii.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).lowercased() == key.lowercased() {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func extractTitle(_ ascii: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: ascii, range: NSRange(ascii.startIndex..., in: ascii)),
              let range = Range(match.range(at: 1), in: ascii) else { return nil }
        return String(ascii[range]).trimmingCharacters(in: .whitespacesAndNewlines).prefix(80).description
    }
}

enum UDPProbe {
    static func payload(for port: Int) -> Data {
        switch port {
        case 161:
            return snmpGetPublicSysDescr()
        case 5683, 5684:
            return coapWellKnownCore()
        case 1900:
            return Data("""
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 1\r
            ST: ssdp:all\r
            \r

            """.utf8)
        case 123:
            return Data([0x1b] + Array(repeating: 0, count: 47))
        case 69:
            return Data("\u{00}\u{01}finch\u{00}octet\u{00}".utf8)
        case 47808:
            return Data(hex: "810a00120120ffff00ff10") ?? Data([0x81, 0x0a])
        case 14540, 14550, 14551, 14552, 14553, 14555, 14560, 14580, 18570:
            return Data([0xfe, 0x09, 0x00, 0xff, 0x01] + Array(repeating: 0, count: 11))
        case 3702:
            return Data("""
            <?xml version="1.0" encoding="UTF-8"?><e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"><e:Header><w:MessageID>uuid:finch</w:MessageID><w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To><w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action></e:Header><e:Body><d:Probe/></e:Body></e:Envelope>
            """.utf8)
        default:
            return Data("\u{00}finch-udp-probe\u{00}".utf8)
        }
    }

    static func snmpGetPublicSysDescr() -> Data {
        // SNMPv1 GET community "public" sysDescr.0 — same shape as Finch fabric_offense
        let com = Data("public".utf8)
        let oid = Data([0x2b, 0x06, 0x01, 0x02, 0x01, 0x01, 0x01, 0x00])
        var vbInner = Data([0x06, UInt8(oid.count)]) + oid + Data([0x05, 0x00])
        var vb = Data([0x30, UInt8(vbInner.count)]) + vbInner
        var pduInner = Data([0x02, 0x01, 0x01, 0x02, 0x01, 0x00, 0x02, 0x01, 0x00]) + vb
        var pdu = Data([0xa0, UInt8(pduInner.count)]) + pduInner
        var msgInner = Data([0x02, 0x01, 0x00, 0x04, UInt8(com.count)]) + com + pdu
        return Data([0x30, UInt8(msgInner.count)]) + msgInner
    }

    static func coapWellKnownCore() -> Data {
        let path = Data(".well-known".utf8)
        let path2 = Data("core".utf8)
        var opts = Data([0xB0 | UInt8(path.count & 0x0F)]) + path
        opts += Data([0x00 | UInt8(path2.count & 0x0F)]) + path2
        return Data([0x50, 0x01, 0x12, 0x34]) + opts
    }

    static func elicit(host: String, port: UInt16, payload: Data, timeout: TimeInterval) async -> Bool {
        let data = await exchange(host: host, port: port, payload: payload, timeout: timeout)
        return data != nil && !(data?.isEmpty ?? true)
    }

    static func exchange(host: String, port: UInt16, payload: Data, timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .udp
            )
            let lock = NSLock()
            var resumed = false
            func finish(_ value: Data?) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { _ in
                        connection.receiveMessage { data, _, _, _ in
                            finish(data)
                        }
                    })
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }
}

private extension Data {
    init?(hex: String) {
        let cleaned = hex.replacingOccurrences(of: " ", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data()
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        self = data
    }
}
