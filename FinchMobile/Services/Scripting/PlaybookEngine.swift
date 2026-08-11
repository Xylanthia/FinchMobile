import Foundation
import Observation

struct PlaybookRule: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var matchClass: String?
    var minThreat: Int?
    var action: String
    var note: String
}

/// Lightweight sandboxed playbook runner (JSON rules). Not a full Lua VM — reacts to fused tracks.
@Observable
final class PlaybookEngine {
    var rules: [PlaybookRule] = []
    var lastFires: [String] = []
    var statusText: String = "Playbooks idle"

    private weak var forensic: ForensicLogger?

    func bind(forensic: ForensicLogger) { self.forensic = forensic }

    func loadBundled() {
        if let url = Bundle.main.url(forResource: "default_playbooks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([PlaybookRule].self, from: data) {
            rules = decoded
        } else {
            rules = Self.builtin
        }
        statusText = "\(rules.count) playbook rule(s)"
    }

    func evaluate(tracks: [RFTrack]) {
        var fires: [String] = []
        for track in tracks {
            for rule in rules {
                if let cls = rule.matchClass, track.deviceClass.rawValue != cls { continue }
                if let min = rule.minThreat, track.threatScore < min { continue }
                let line = "[\(rule.id)] \(rule.action) → \(track.displayName)"
                fires.append(line)
                forensic?.record(category: "playbook", summary: line, detail: rule.note)
            }
        }
        if !fires.isEmpty {
            lastFires = Array(fires.prefix(30))
            statusText = "Fired \(fires.count) action(s)"
        }
    }

    static let builtin: [PlaybookRule] = [
        PlaybookRule(id: "flipper-watch", title: "Flipper appears", matchClass: "flipper", minThreat: 5,
                     action: "forensic.log + elevate UI", note: "Flag Flipper Zero-class advertisers"),
        PlaybookRule(id: "drone-alert", title: "Drone class", matchClass: "drone", minThreat: 4,
                     action: "forensic.log + open Drone panel hint", note: "Passive drone situational awareness"),
        PlaybookRule(id: "critical-any", title: "Critical threat", matchClass: nil, minThreat: 8,
                     action: "forensic.log CRITICAL", note: "Any track scoring 8+")
    ]
}
