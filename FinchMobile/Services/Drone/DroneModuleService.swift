import Foundation
import Observation

/// Passive drone detection + auth-gated active-op stubs.
/// Stock iOS cannot Tx RF / MITM / GPS-spoof. Those paths require external authorized kit and only audit here.
@Observable
final class DroneModuleService {
    var detections: [RFTrack] = []
    var statusText: String = "Drone module passive"
    var lastActiveResult: String?

    private var consent: ConsentGate?
    private var forensic: ForensicLogger?

    func bind(consent: ConsentGate, forensic: ForensicLogger) {
        self.consent = consent
        self.forensic = forensic
    }

    func refresh(from tracks: [RFTrack]) {
        detections = tracks.filter {
            $0.deviceClass == .drone || $0.deviceClass == .droneController || ($0.droneMeta != nil)
        }.sorted { $0.threatScore > $1.threatScore }
        statusText = detections.isEmpty
            ? "No drone-class tracks"
            : "\(detections.count) drone-class track(s)"
    }

    /// Passive: mark observation of MAVLink-like TCP (already discovered via Glass). No Tx.
    func observeMAVLink(trackId: UUID) {
        forensic?.record(category: "drone", summary: "MAVLink observe requested", detail: trackId.uuidString)
        lastActiveResult = "Observe-only: use Glass Deep Scan on ports 5760–5763. No MAVLink frames sent."
        statusText = lastActiveResult ?? statusText
    }

    /// Active ops: consent + arm required. On stock iPhone these do NOT transmit — they refuse with kit notice.
    func requestActive(kind: ActiveOpKind, track: RFTrack) -> String {
        guard let consent else { return "Consent gate unavailable" }
        if let denial = consent.authorize(kind, targetId: track.id.uuidString, note: track.displayName) {
            forensic?.record(category: "drone.deny", summary: denial, detail: kind.rawValue)
            lastActiveResult = "DENIED: \(denial)"
            return lastActiveResult!
        }
        guard let op = consent.confirmPending() else {
            return "No pending op"
        }
        forensic?.record(
            category: "drone.active",
            summary: "Authorized \(op.kind.title) for \(track.displayName)",
            detail: "target=\(op.targetId) kitRequired=\(op.kind.requiresExternalRFKit)"
        )

        if op.kind.requiresExternalRFKit {
            lastActiveResult = """
            AUTHORIZED & LOGGED — \(op.kind.title).
            Stock iOS cannot perform RF Tx / MITM / spoof / jam.
            Connect an authorized external SDR / C2 kit; Finch remains the consent + forensic bridge.
            """
        } else {
            lastActiveResult = "AUTHORIZED — \(op.kind.title) (passive path)."
        }
        statusText = "Last op: \(op.kind.title)"
        return lastActiveResult!
    }
}
