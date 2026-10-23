import Foundation

/// Local-AP HTTP client for the ARIA handheld. No cloud relay, no pairing — talks straight
/// to the device over the ARIA-Setup Wi-Fi AP (default 192.168.4.1), same trust boundary as
/// standing in front of it (spec §1, §1.6).
final class ARIAClient {
    struct Failure: Error {
        var message: String
        var statusCode: Int?
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
        let data = try await getData("/tool_outputs/results")
        return ARIASessionParser.parse(data)
    }

    func fetchSummary() async throws -> ARIASessionSummary {
        try await get("/info/gui", as: ARIASessionSummary.self)
    }

    // MARK: - Action registry discovery (§1.5)
    // Walk into each mode/page, not just the 7-item top-level menu. The device exposes the
    // full action set the same way ACTION_FUNCTIONALITY_MATRIX.md is built on the firmware side.

    private struct RegistryModeDTO: Decodable {
        var name: String
        var command: String?
        var actions: [ARIAAction]?
    }

    private struct RegistryDTO: Decodable {
        var modes: [RegistryModeDTO]?
        var actions: [ARIAAction]?   // some firmwares emit a flat action list with group/page
    }

    /// Fetch the device's full action/mode registry. Prefers a dedicated registry endpoint;
    /// falls back to grouping a flat action list by its GROUP column.
    func fetchActionRegistry() async throws -> [ARIAMode] {
        let dto: RegistryDTO = try await get("/info/gui", as: RegistryDTO.self)

        if let modes = dto.modes, !modes.isEmpty {
            return modes.map {
                ARIAMode(name: $0.name, command: $0.command, actions: $0.actions ?? [])
            }
        }

        // Fall back: flat action list → group two levels deep by GROUP/PAGE.
        if let actions = dto.actions, !actions.isEmpty {
            let grouped = Dictionary(grouping: actions) { $0.group ?? $0.name }
            return grouped
                .map { key, value in ARIAMode(name: key, command: nil, actions: value) }
                .sorted { $0.name < $1.name }
        }

        throw Failure(message: "device returned no action registry", statusCode: nil)
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
