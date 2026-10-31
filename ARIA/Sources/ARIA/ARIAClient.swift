import Foundation

/// Local-AP HTTP client for the ARIA handheld. No cloud relay, no pairing — talks straight
/// to the device over the ARIA-Setup Wi-Fi AP (default 192.168.4.1), same trust boundary as
/// standing in front of it (spec §1, §1.6).
final class ARIAClient {
    struct Failure: LocalizedError {
        var message: String
        var statusCode: Int?
        var errorDescription: String? { message }
    }

    /// Default AP gateway. Overridable if the device enumerates a different IP.
    var baseURL: URL

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral   // offline-first, nothing persisted
        config.timeoutIntervalForRequest = 8             // conservative for ESP32 over AP
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "ARIA-iOS/1.0",
            "Accept": "application/json"
        ]
        return URLSession(configuration: config)
    }()

    init(baseURL: URL = URL(string: "http://192.168.4.1")!) {
        self.baseURL = baseURL
    }

    private func url(_ path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://"), let u = URL(string: path) {
            return u
        }
        return URL(string: path, relativeTo: baseURL) ?? baseURL
    }

    // MARK: - Reachability probe (§2)

    /// Cheap liveness check distinct from "not on ARIA network".
    func ping() async -> Bool {
        var req = URLRequest(url: url("/info/gui"))
        req.httpMethod = "GET"
        do {
            let (_, resp) = try await session.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Raw GET

    func getData(_ path: String) async throws -> Data {
        var req = URLRequest(url: url(path))
        req.httpMethod = "GET"
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw Failure(message: "HTTP \(code) for \(path)", statusCode: code)
            }
            return data
        } catch let f as Failure {
            throw f
        } catch {
            throw Failure(message: error.localizedDescription, statusCode: nil)
        }
    }

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await getData(path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Failure(message: "decode failed for \(path): \(error)", statusCode: nil)
        }
    }

    // MARK: - Session export (full dump, §1 — parsed resiliently in §4)

    func fetchSessionExport() async throws -> ARIASessionExport {
        // Export data_ref/output_ref strings are JSON pointers, not HTTP routes.
        // /api/export enters download mode and pauses scanning, so never poll it.
        let data = try await getData("/api/devices")
        let devices = try ARIAJSONResponse.object(data, endpoint: "/api/devices")
        guard devices["devices"] is [Any] else {
            throw ARIAJSONResponse.Failure(message: "/api/devices: missing devices array")
        }
        var root: [String: Any] = ["session": devices, "schema": "finch.aria.live.v1"]
        var warnings: [String] = []
        for (key, endpoint) in [("subghz_live", "/api/subghz/raw?n=50")] {
            do {
                root[key] = try ARIAJSONResponse.object(try await getData(endpoint), endpoint: endpoint)
            } catch {
                warnings.append(error.localizedDescription)
            }
        }
        root["poll_warnings"] = warnings
        let snapshot = try ARIAJSONResponse.session(root)
        return snapshot
    }

    func fetchSummary() async throws -> ARIASessionSummary {
        let root = try ARIAJSONResponse.object(try await getData("/api/ping"), endpoint: "/api/ping")
        return ARIASessionSummary(uptimeSeconds: (root["uptime_ms"] as? Int).map { $0 / 1000 },
                                  heapFree: root["heap_free"] as? Int)
    }

    // MARK: - Fire a control (§1.5 / §1.6)

    /// Fire a registry action's command over the AP. Result is the device's response body.
    /// On AP drop mid-flight the caller treats the outcome as UNKNOWN — never assume success.
    @discardableResult
    func fire(_ action: ARIAAction) async throws -> Data {
        let command = action.command ?? action.name
        guard !command.isEmpty else {
            throw Failure(message: "action has no command", statusCode: nil)
        }
        let encoded = command.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? command
        return try await getData("/api/cmd?run=\(encoded)")
    }

    /// Replay a captured Sub-GHz sequence via its raw_capture_ref (§3.4).
    @discardableResult
    func replaySubGHz(_ capture: ARIASubGHzCapture) async throws -> Data {
        try await getData(capture.replayPath)
    }

    // MARK: - Handheld decoder for phone-scanned BLE (/api/decode/ble)

    func decodeBLE(advHex: String) async throws -> [String: Any] {
        try ARIAJSONResponse.object(try await getData("/api/decode/ble?adv=\(advHex)"), endpoint: "/api/decode/ble")
    }

    // MARK: - Omni command evidence (/api/omni)

    /// Runs a read-only omni command whose "output" is itself JSON (evidence pages) and
    /// returns that inner object. The handheld refuses these while in download mode.
    func omniJSON(_ command: String) async throws -> [String: Any] {
        var components = URLComponents(url: url("/api/omni"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "cmd", value: command)]
        guard let target = components?.url else { throw Failure(message: "bad omni command", statusCode: nil) }
        let outer = try ARIAJSONResponse.object(try await getData(target.absoluteString), endpoint: "/api/omni \(command)")
        guard let text = outer["output"] as? String, let data = text.data(using: .utf8) else {
            throw Failure(message: "\(command): no output", statusCode: nil)
        }
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw Failure(message: "\(command): \(String(text.prefix(140)))", statusCode: nil)   // e.g. download mode notice
        }
        return try ARIAJSONResponse.object(data, endpoint: command)
    }

    // MARK: - Persistent capture log (firmware aria_log.h)

    /// History pages and the event stream are long transfers over the AP; they get their own
    /// session so the 8 s / 15 s snapshot timeouts above never cut them off.
    private let longSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45            // idle gap; the stream pings every 15 s
        config.timeoutIntervalForResource = 7 * 24 * 3600
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["User-Agent": "ARIA-iOS/1.0"]
        return URLSession(configuration: config)
    }()

    private func getLong(_ path: String) async throws -> Data {
        // The log answers 503 BUSY while its writer holds the flash lock; that is a retry, not a failure.
        var attempt = 0
        while true {
            let (data, resp) = try await longSession.data(from: url(path))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) { return data }
            attempt += 1
            if code != 503 || attempt >= 6 {
                let body = String(decoding: data.prefix(160), as: UTF8.self)
                throw Failure(message: "HTTP \(code) for \(path) \(body)", statusCode: code)
            }
            try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
        }
    }

    /// GET /api/log/stats — the handheld's own per-source totals.
    func logStats() async throws -> [String: Any] {
        try ARIAJSONResponse.object(try await getLong("/api/log/stats"), endpoint: "/api/log/stats")
    }

    /// GET /api/log — records with seq > sinceSeq, oldest first.
    func logPage(_ source: ARIALogSource, sinceSeq: Int, limit: Int) async throws -> [String: Any] {
        let path = "/api/log?source=\(source.rawValue)&since_seq=\(sinceSeq)&limit=\(limit)"
        return try ARIAJSONResponse.object(try await getLong(path), endpoint: path)
    }

    struct StreamEvent {
        var id: String?
        var event = "message"
        var data = ""
    }

    /// GET /api/stream (Server-Sent Events). Ends when the connection drops; the caller
    /// reconnects with the last id and re-pages /api/log from its cursors to cover any gap.
    func events(lastEventID: String?) -> AsyncThrowingStream<StreamEvent, Error> {
        let request: URLRequest = {
            var req = URLRequest(url: url("/api/stream"))
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            if let lastEventID { req.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID") }
            return req
        }()
        let session = longSession
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, resp) = try await session.bytes(for: request)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard code == 200 else { throw Failure(message: "HTTP \(code) for /api/stream", statusCode: code) }
                    // Parsed by hand: AsyncBytes.lines skips the blank lines that end SSE events.
                    var line: [UInt8] = []
                    var event = StreamEvent()
                    for try await byte in bytes {
                        guard byte == 0x0A else { line.append(byte); continue }
                        if line.last == 0x0D { line.removeLast() }
                        if line.isEmpty {
                            if !event.data.isEmpty { continuation.yield(event) }
                            event = StreamEvent(id: event.id)
                        } else if line.first != 0x3A {   // ':' = comment
                            let text = String(decoding: line, as: UTF8.self)
                            let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                            var value = parts.count > 1 ? String(parts[1]) : ""
                            if value.hasPrefix(" ") { value.removeFirst() }
                            switch parts[0] {
                            case "id": event.id = value
                            case "event": event.event = value
                            case "data": event.data += event.data.isEmpty ? value : "\n" + value
                            default: break
                            }
                        }
                        line.removeAll(keepingCapacity: true)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
