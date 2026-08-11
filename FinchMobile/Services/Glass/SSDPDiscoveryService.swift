import Foundation
import Network

struct SSDPDevice: Hashable {
    var ip: String
    var location: String?
    var server: String?
    var usn: String?
    var st: String?
    var friendlyHint: String?
}

final class SSDPDiscoveryService {
    var onUpdate: (([SSDPDevice]) -> Void)?

    private var connection: NWConnection?
    private var devices: [String: SSDPDevice] = [:]
    private let queue = DispatchQueue(label: "com.aetherverse.finch.ssdp")

    func start(duration: TimeInterval = 4.0) {
        stop()
        devices.removeAll()

        let host = NWEndpoint.Host("239.255.255.250")
        guard let port = NWEndpoint.Port(rawValue: 1900) else { return }
        let connection = NWConnection(host: host, port: port, using: .udp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendMSearch(on: connection)
                self.receiveLoop(on: connection)
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.stop()
            self?.publish()
        }
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }

    func snapshot() -> [SSDPDevice] {
        Array(devices.values).sorted { $0.ip < $1.ip }
    }

    private func sendMSearch(on connection: NWConnection) {
        let payload = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: ssdp:all\r
        USER-AGENT: FinchMobile/2.0 UPnP/1.1\r
        \r

        """
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
        // Second burst improves hit rate on flaky LAN
        queue.asyncAfter(deadline: .now() + 0.6) {
            connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
        }
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let text = String(data: data, encoding: .utf8) {
                self.parseResponse(text)
            }
            if error == nil, self.connection != nil {
                self.receiveLoop(on: connection)
            }
        }
    }

    private func parseResponse(_ text: String) {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first?.uppercased().contains("HTTP/") == true else { return }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            headers[key] = val
        }

        let location = headers["LOCATION"]
        let server = headers["SERVER"]
        let usn = headers["USN"]
        let st = headers["ST"] ?? headers["NT"]

        let ip = extractIP(from: location) ?? extractIP(from: usn)
        guard let ip else { return }

        var hint: String?
        if let st, !st.isEmpty { hint = st }
        if let server, !server.isEmpty { hint = (hint.map { "\($0) · " } ?? "") + server }

        let device = SSDPDevice(
            ip: ip,
            location: location,
            server: server,
            usn: usn,
            st: st,
            friendlyHint: hint
        )
        devices[ip + "|" + (usn ?? location ?? st ?? "")] = device
        publish()
    }

    private func extractIP(from value: String?) -> String? {
        guard let value else { return nil }
        // http://192.168.1.10:8080/desc.xml
        if let regex = try? NSRegularExpression(pattern: #"(\d{1,3}(?:\.\d{1,3}){3})"#),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let range = Range(match.range(at: 1), in: value) {
            return String(value[range])
        }
        return nil
    }

    private func publish() {
        let snap = snapshot()
        DispatchQueue.main.async {
            self.onUpdate?(snap)
        }
    }
}
