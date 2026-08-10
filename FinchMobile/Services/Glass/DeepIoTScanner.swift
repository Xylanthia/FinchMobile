import Foundation

final class DeepIoTScanner {
    var onBanner: ((String, Banner) -> Void)?
    var onPortOpen: ((String, Int) -> Void)?
    var onProgress: ((String) -> Void)?

    func scanHost(_ ip: String, ports: [Int] = IoTPorts.surface, maxConcurrent: Int = 40) async -> (openPorts: [Int], banners: [Banner]) {
        var openPorts: [Int] = []
        var banners: [Banner] = []

        await withTaskGroup(of: (Int, Bool, Banner?).self) { group in
            var inFlight = 0
            var index = 0

            func enqueue() {
                while inFlight < maxConcurrent && index < ports.count {
                    let port = ports[index]
                    index += 1
                    inFlight += 1
                    group.addTask {
                        let isOpen = await TCPProbe.isOpen(host: ip, port: UInt16(port), timeout: 1.2)
                        if !isOpen { return (port, false, nil) }
                        let banner = await BannerGrabber.grab(host: ip, port: port)
                        return (port, true, banner)
                    }
                }
            }

            enqueue()
            var done = 0
            for await (port, isOpen, banner) in group {
                inFlight -= 1
                done += 1
                if done % 8 == 0 || done == ports.count {
                    onProgress?("Deep scan \(ip): \(done)/\(ports.count)")
                }
                if isOpen {
                    openPorts.append(port)
                    onPortOpen?(ip, port)
                    if let banner {
                        banners.append(banner)
                        onBanner?(ip, banner)
                    } else {
                        banners.append(
                            Banner(
                                port: port,
                                protocolGuess: IoTPorts.family(for: port),
                                rawASCII: "",
                                rawHex: "",
                                headers: [:]
                            )
                        )
                    }
                }
                enqueue()
            }
        }

        return (openPorts.sorted(), banners.sorted { $0.port < $1.port })
    }
}

enum BannerGrabber {
    static func grab(host: String, port: Int) async -> Banner? {
        let family = IoTPorts.family(for: port)
        let send: Data?
        let timeout: TimeInterval

        switch family {
        case "http", "home-assistant", "nodered", "elasticsearch":
            let req = "HEAD / HTTP/1.0\r\nHost: \(host)\r\nUser-Agent: FinchMobile/1.1\r\nConnection: close\r\n\r\n"
            send = Data(req.utf8)
            timeout = 2.5
        case "rtsp", "dahua", "hikvision-dvr":
            send = Data("OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n".utf8)
            timeout = 2.5
        case "mqtt":
            send = MQTTPacket.connect(clientID: "finch-probe", cleanSession: true)
            timeout = 2.5
        case "ftp":
            send = nil
            timeout = 2.0
        case "redis":
            send = Data("INFO\r\n".utf8)
            timeout = 2.0
        case "ssh", "telnet", "adb":
            send = nil
            timeout = 2.0
        default:
            send = nil
            timeout = 2.0
        }

        guard let data = await TCPProbe.connectAndIO(
            host: host,
            port: UInt16(port),
            timeout: timeout,
            send: send,
            readLimit: 4096
        ), !data.isEmpty else {
            return nil
        }

        let ascii = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let headers = parseHeaders(ascii)

        return Banner(
            port: port,
            protocolGuess: family,
            rawASCII: String(ascii.prefix(4096)),
            rawHex: hex,
            headers: headers
        )
    }

    private static func parseHeaders(_ ascii: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = ascii.split(whereSeparator: \.isNewline)
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = val }
        }
        if let first = lines.first {
            result["status-line"] = String(first)
        }
        return result
    }
}
