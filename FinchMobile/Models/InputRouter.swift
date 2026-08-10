import Foundation

enum PipelineKind: String, CaseIterable, Identifiable, Codable {
    case auto
    case glassFabric
    case ble

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "AUTO"
        case .glassFabric: return "GLASS"
        case .ble: return "BLE"
        }
    }
}

enum InputRouter {
    static func classify(_ raw: String) -> PipelineKind {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()

        if lower == "scan ble" || lower == "ble radar" || lower == "scanble" {
            return .ble
        }

        if isCIDR(q) || isPrivateIP(q) || lower == "scan my network" || lower == "scan network" {
            return .glassFabric
        }

        // Fallback: treat bare private-looking hosts / local hostnames as glass
        if q.contains("/") && q.split(separator: "/").count == 2 {
            return .glassFabric
        }

        return .glassFabric
    }

    static func resolve(query: String, override: PipelineKind) -> PipelineKind {
        override == .auto ? classify(query) : override
    }

    static func isCIDR(_ s: String) -> Bool {
        let parts = s.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 32 else { return false }
        return isIPv4(String(parts[0]))
    }

    static func isPrivateIP(_ s: String) -> Bool {
        guard isIPv4(s) else { return false }
        let octets = s.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        if octets[0] == 10 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        if octets[0] == 127 { return true }
        return false
    }

    static func isIPv4(_ s: String) -> Bool {
        let octets = s.split(separator: ".")
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { part in
            guard let n = Int(part), (0...255).contains(n) else { return false }
            return true
        }
    }

    static func isPublicIPv4(_ s: String) -> Bool {
        isIPv4(s) && !isPrivateIP(s)
    }
}
