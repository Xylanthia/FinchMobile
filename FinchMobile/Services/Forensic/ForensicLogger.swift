import Foundation
import CryptoKit
import Observation

struct ForensicEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var timestamp: Date
    var category: String
    var summary: String
    var detail: String
    var prevHash: String
    var hash: String
}

/// Append-only chain-of-custody log. Each event hashes previous hash + payload (SHA-256).
@Observable
final class ForensicLogger {
    var events: [ForensicEvent] = []
    private(set) var tipHash: String = String(repeating: "0", count: 64)
    var researchMode: Bool = false

    func record(category: String, summary: String, detail: String = "") {
        let ts = Date()
        let id = UUID()
        let payload = [
            id.uuidString,
            String(ts.timeIntervalSince1970),
            category,
            summary,
            detail,
            tipHash
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let event = ForensicEvent(
            id: id, timestamp: ts, category: category,
            summary: summary, detail: detail,
            prevHash: tipHash, hash: hex
        )
        events.insert(event, at: 0)
        tipHash = hex
        if events.count > 2000 { events.removeLast(events.count - 2000) }
    }

    func exportChainJSON() throws -> Data {
        let envelope: [String: Any] = [
            "schema": "finch.forensic.v1",
            "tipHash": tipHash,
            "count": events.count,
            "events": events.map { e -> [String: Any] in
                [
                    "id": e.id.uuidString,
                    "ts": ISO8601DateFormatter().string(from: e.timestamp),
                    "category": e.category,
                    "summary": e.summary,
                    "detail": e.detail,
                    "prevHash": e.prevHash,
                    "hash": e.hash
                ]
            }
        ]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
    }

    func clear() {
        events.removeAll()
        tipHash = String(repeating: "0", count: 64)
        record(category: "system", summary: "Forensic chain reset")
    }
}
