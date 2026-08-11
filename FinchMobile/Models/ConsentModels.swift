import Foundation
import CryptoKit

/// Cryptographically signed operator consent token required before any active (Tx) operation.
struct ConsentToken: Codable, Hashable, Identifiable {
    var id: UUID
    var subject: String
    var scope: [String]
    var issuedAt: Date
    var expiresAt: Date
    var issuer: String
    var waiverSynthetic: Bool
    var signatureHex: String

    var isExpired: Bool { Date() > expiresAt }

    func allows(_ action: String) -> Bool {
        !isExpired && (scope.contains("*") || scope.contains(action))
    }
}

enum ActiveOpKind: String, Codable, CaseIterable, Identifiable {
    case armSystem
    case bleWrite
    case mavlinkObserve
    case mavlinkCommand
    case mitmSession
    case injectFrame
    case fuzzTarget
    case gpsSpoof
    case rfJam
    case meshRemoteArm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .armSystem: return "Arm engagement"
        case .bleWrite: return "BLE characteristic write"
        case .mavlinkObserve: return "MAVLink observe (Rx)"
        case .mavlinkCommand: return "MAVLink command (Tx)"
        case .mitmSession: return "MITM session"
        case .injectFrame: return "Frame injection"
        case .fuzzTarget: return "Protocol fuzz"
        case .gpsSpoof: return "GPS spoof"
        case .rfJam: return "RF deny"
        case .meshRemoteArm: return "Mesh remote arm"
        }
    }

    /// True ops that would require external RF kit on stock iOS.
    var requiresExternalRFKit: Bool {
        switch self {
        case .mavlinkObserve, .armSystem: return false
        default: return true
        }
    }
}

struct ActiveOpRequest: Identifiable, Codable {
    var id: UUID
    var kind: ActiveOpKind
    var targetId: String
    var requestedAt: Date
    var note: String
}
