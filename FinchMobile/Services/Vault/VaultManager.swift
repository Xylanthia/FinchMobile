import Foundation
import CryptoKit
import LocalAuthentication
import SwiftData
import Security
import Observation

@Model
final class VaultItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var ciphertext: Data
    var nonce: Data
    var tag: Data
    var schemaVersion: Int

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), ciphertext: Data, nonce: Data, tag: Data, schemaVersion: Int = 1) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.tag = tag
        self.schemaVersion = schemaVersion
    }
}

enum VaultCrypto {
    static func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        let input = SymmetricKey(data: Data(passphrase.utf8))
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input,
            salt: salt,
            info: Data("finch.mobile.vault.v1".utf8),
            outputByteCount: 32
        )
        return derived
    }

    static func encrypt(plaintext: Data, key: SymmetricKey) throws -> (ciphertext: Data, nonce: Data, tag: Data) {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw VaultError.sealFailed
        }
        // combined = nonce (12) + ciphertext + tag (16)
        let nonce = Data(combined.prefix(12))
        let tag = Data(combined.suffix(16))
        let ciphertext = Data(combined.dropFirst(12).dropLast(16))
        return (ciphertext, nonce, tag)
    }

    static func decrypt(ciphertext: Data, nonce: Data, tag: Data, key: SymmetricKey) throws -> Data {
        let nonceBox = try AES.GCM.Nonce(data: nonce)
        let box = try AES.GCM.SealedBox(nonce: nonceBox, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(box, using: key)
    }
}

enum VaultError: LocalizedError {
    case sealFailed
    case authFailed
    case noPassphrase
    case decryptFailed

    var errorDescription: String? {
        switch self {
        case .sealFailed: return "Encryption failed"
        case .authFailed: return "Biometric authentication failed"
        case .noPassphrase: return "Set a vault passphrase in Settings"
        case .decryptFailed: return "Unable to decrypt vault item"
        }
    }
}

@Observable
final class VaultManager {
    private(set) var unlockedKey: SymmetricKey?
    private(set) var isUnlocked: Bool = false
    var lastError: String?

    private let saltKey = "finch.vault.salt"
    private let passKey = "finch.vault.passphrase"

    func wipeKeyOnBackground() {
        unlockedKey = nil
        isUnlocked = false
    }

    func ensureSalt() -> Data {
        if let existing = KeychainStore.load(account: saltKey) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let salt = Data(bytes)
        KeychainStore.save(account: saltKey, data: salt)
        return salt
    }

    func setPassphrase(_ passphrase: String) {
        KeychainStore.save(account: passKey, data: Data(passphrase.utf8))
        let salt = ensureSalt()
        unlockedKey = VaultCrypto.deriveKey(passphrase: passphrase, salt: salt)
        isUnlocked = true
    }

    func hasPassphrase() -> Bool {
        KeychainStore.load(account: passKey) != nil
    }

    @MainActor
    func authenticateBiometric(reason: String = "Unlock Finch Vault") async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
                || context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Fall back to passphrase-only unlock
            return unlockWithStoredPassphrase()
        }
        do {
            let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
                ? .deviceOwnerAuthenticationWithBiometrics
                : .deviceOwnerAuthentication
            let ok = try await context.evaluatePolicy(policy, localizedReason: reason)
            if ok {
                return unlockWithStoredPassphrase()
            }
            return false
        } catch {
            lastError = error.localizedDescription
            return unlockWithStoredPassphrase()
        }
    }

    func unlockWithStoredPassphrase() -> Bool {
        guard let data = KeychainStore.load(account: passKey),
              let passphrase = String(data: data, encoding: .utf8) else {
            lastError = VaultError.noPassphrase.localizedDescription
            return false
        }
        let salt = ensureSalt()
        unlockedKey = VaultCrypto.deriveKey(passphrase: passphrase, salt: salt)
        isUnlocked = true
        return true
    }

    func persist(reportJSON: Data, title: String, context: ModelContext) throws {
        guard let key = unlockedKey ?? {
            _ = unlockWithStoredPassphrase()
            return unlockedKey
        }() else {
            throw VaultError.noPassphrase
        }
        let sealed = try VaultCrypto.encrypt(plaintext: reportJSON, key: key)
        let item = VaultItem(
            title: title,
            ciphertext: sealed.ciphertext,
            nonce: sealed.nonce,
            tag: sealed.tag
        )
        context.insert(item)
        try context.save()
    }

    func decrypt(_ item: VaultItem) throws -> Data {
        guard let key = unlockedKey else { throw VaultError.authFailed }
        do {
            return try VaultCrypto.decrypt(
                ciphertext: item.ciphertext,
                nonce: item.nonce,
                tag: item.tag,
                key: key
            )
        } catch {
            throw VaultError.decryptFailed
        }
    }

    func clearAll(context: ModelContext, items: [VaultItem]) throws {
        for item in items {
            context.delete(item)
        }
        try context.save()
    }
}

enum KeychainStore {
    static func save(account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "com.aetherverse.finchmobile"
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "com.aetherverse.finchmobile",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "com.aetherverse.finchmobile"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@Observable
final class SettingsStore {
    var continuousBLEDefault: Bool {
        get { UserDefaults.standard.object(forKey: "continuousBLE") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "continuousBLE") }
    }

    var mqttUsername: String {
        get { UserDefaults.standard.string(forKey: "mqttUser") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "mqttUser") }
    }

    var mqttPassword: String {
        get {
            if let d = KeychainStore.load(account: "mqtt.password"), let s = String(data: d, encoding: .utf8) {
                return s
            }
            return ""
        }
        set { KeychainStore.save(account: "mqtt.password", data: Data(newValue.utf8)) }
    }

    var fingerprintUpdateURL: String {
        get { UserDefaults.standard.string(forKey: "fpUpdateURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "fpUpdateURL") }
    }


    var hibpApiKey: String {
        get {
            if let d = KeychainStore.load(account: "osint.hibp"), let s = String(data: d, encoding: .utf8) { return s }
            return ""
        }
        set { KeychainStore.save(account: "osint.hibp", data: Data(newValue.utf8)) }
    }

    /// EmailOSINT.org bearer key (`eo_…`) — linked accounts, breaches, AI summary.
    var emailOsintApiKey: String {
        get {
            if let d = KeychainStore.load(account: "osint.emailosint"), let s = String(data: d, encoding: .utf8) { return s }
            return ""
        }
        set { KeychainStore.save(account: "osint.emailosint", data: Data(newValue.utf8)) }
    }

    /// NumlookupAPI key — phone carrier / line-type / location (emailosint-style for numbers).
    var numlookupApiKey: String {
        get {
            if let d = KeychainStore.load(account: "osint.numlookup"), let s = String(data: d, encoding: .utf8) { return s }
            return ""
        }
        set { KeychainStore.save(account: "osint.numlookup", data: Data(newValue.utf8)) }
    }

    var etherscanApiKey: String {
        get {
            if let d = KeychainStore.load(account: "osint.etherscan"), let s = String(data: d, encoding: .utf8) { return s }
            return ""
        }
        set { KeychainStore.save(account: "osint.etherscan", data: Data(newValue.utf8)) }
    }

    var shodanApiKey: String {
        get {
            if let d = KeychainStore.load(account: "osint.shodan"), let s = String(data: d, encoding: .utf8) { return s }
            return ""
        }
        set { KeychainStore.save(account: "osint.shodan", data: Data(newValue.utf8)) }
    }

    var researchMode: Bool {
        get { UserDefaults.standard.bool(forKey: "researchMode") }
        set { UserDefaults.standard.set(newValue, forKey: "researchMode") }
    }

    /// Desktop Finch backend, e.g. http://192.168.1.42:8765 — same rails as the web app.
    var finchBackendURL: String {
        get { UserDefaults.standard.string(forKey: "finchBackendURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "finchBackendURL") }
    }
}
