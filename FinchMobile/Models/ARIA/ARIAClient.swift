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
            "User-Agent": "FinchMobile/3.2 (ARIA module)",
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
        for (key, endpoint) in [("subghz_live", "/api/subghz/raw?n=50"), ("rfid", "/api/rfid")] {
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
}
