import Foundation
import CryptoKit
import Observation

/// Passive-by-default gate. Active ops require a loaded HMAC-signed consent token + user confirm + arm flag.
@Observable
final class ConsentGate {
    var token: ConsentToken?
    var isArmed: Bool = false
    var killSwitchEngaged: Bool = true
    var lastDenial: String?
    var pendingOp: ActiveOpRequest?
    var auditLine: String = "PASSIVE · kill-switch ON"

    private let signingSecretAccount = "consent.signing.secret"

    var hasValidToken: Bool {
        guard let token, !token.isExpired else { return false }
        return verify(token)
    }

    var statusSummary: String {
        if killSwitchEngaged { return "KILL SWITCH · transmissions locked" }
        if !isArmed { return "DISARMED · passive only" }
        if hasValidToken { return "ARMED · consent \(token?.subject ?? "?")" }
        return "ARMED but NO valid consent token"
    }

    func ensureSigningSecret() -> Data {
        if let existing = KeychainStore.load(account: signingSecretAccount) { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        KeychainStore.save(account: signingSecretAccount, data: data)
        return data
    }

    /// Issue a local research/synthetic consent token (operator-owned device / lab waiver).
    func issueLocalToken(
        subject: String,
        scope: [String],
        hoursValid: Double,
        waiverSynthetic: Bool
    ) -> ConsentToken {
        let secret = ensureSigningSecret()
        let id = UUID()
        let issued = Date()
        let expires = issued.addingTimeInterval(hoursValid * 3600)
        let payload = Self.canonicalPayload(
            id: id, subject: subject, scope: scope,
            issuedAt: issued, expiresAt: expires,
            issuer: "finch.local", waiverSynthetic: waiverSynthetic
        )
        let sig = Self.hmacHex(payload: payload, key: secret)
        let token = ConsentToken(
            id: id, subject: subject, scope: scope,
            issuedAt: issued, expiresAt: expires,
            issuer: "finch.local", waiverSynthetic: waiverSynthetic,
            signatureHex: sig
        )
        self.token = token
        refreshAudit()
        return token
    }

    func loadToken(_ token: ConsentToken) -> Bool {
        guard verify(token) else {
            lastDenial = "Invalid consent signature"
            return false
        }
        guard !token.isExpired else {
            lastDenial = "Consent token expired"
            return false
        }
        self.token = token
        lastDenial = nil
        refreshAudit()
        return true
    }

    func clearToken() {
        token = nil
        isArmed = false
        killSwitchEngaged = true
        refreshAudit()
    }

    func engageKillSwitch() {
        killSwitchEngaged = true
        isArmed = false
        pendingOp = nil
        refreshAudit()
    }

    func attemptArm() -> Bool {
        guard !killSwitchEngaged else {
            lastDenial = "Kill switch engaged — flip off in Consent"
            return false
        }
        guard hasValidToken else {
            lastDenial = "Load a signed consent token before arming"
            return false
        }
        isArmed = true
        lastDenial = nil
        refreshAudit()
        return true
    }

    /// Returns nil if allowed to proceed to confirmation; otherwise denial reason.
    func authorize(_ kind: ActiveOpKind, targetId: String, note: String = "") -> String? {
        if killSwitchEngaged { return "Kill switch engaged" }
        if !isArmed { return "System not armed" }
        guard let token, verify(token), !token.isExpired else { return "No valid consent token" }
        guard token.allows(kind.rawValue) || token.allows("*") else {
            return "Token scope excludes \(kind.rawValue)"
        }
        if kind.requiresExternalRFKit {
            // Still require consent, but callers must not transmit — they log + show kit required.
        }
        pendingOp = ActiveOpRequest(id: UUID(), kind: kind, targetId: targetId, requestedAt: Date(), note: note)
        return nil
    }

    func confirmPending() -> ActiveOpRequest? {
        let op = pendingOp
        pendingOp = nil
        return op
    }

    func cancelPending() { pendingOp = nil }

    func verify(_ token: ConsentToken) -> Bool {
        let secret = ensureSigningSecret()
        let payload = Self.canonicalPayload(
            id: token.id, subject: token.subject, scope: token.scope,
            issuedAt: token.issuedAt, expiresAt: token.expiresAt,
            issuer: token.issuer, waiverSynthetic: token.waiverSynthetic
        )
        let expected = Self.hmacHex(payload: payload, key: secret)
        return expected == token.signatureHex
    }

    private func refreshAudit() {
        auditLine = "\(statusSummary) · \(ISO8601DateFormatter().string(from: Date()))"
    }

    private static func canonicalPayload(
        id: UUID, subject: String, scope: [String],
        issuedAt: Date, expiresAt: Date, issuer: String, waiverSynthetic: Bool
    ) -> String {
        let scopes = scope.sorted().joined(separator: ",")
        return [
            id.uuidString,
            subject,
            scopes,
            String(issuedAt.timeIntervalSince1970),
            String(expiresAt.timeIntervalSince1970),
            issuer,
            waiverSynthetic ? "1" : "0"
        ].joined(separator: "|")
    }

    private static func hmacHex(payload: String, key: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: SymmetricKey(data: key))
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
