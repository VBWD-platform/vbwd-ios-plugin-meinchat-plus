import Foundation
import CryptoKit
import Security

/// Stores the device-identity private bytes for `meinchat-plus` (S28.7 §3.1).
/// **Scaffold only** — the *actual* Signal `IdentityKeyPair` lives in
/// `LibSignalClient`, which is not yet vendored. This store wraps the raw
/// 32-byte private key with the same Keychain access controls the sprint
/// specifies (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
///
/// Once `LibSignalClient` lands, the body becomes `set(_:)`/`get()` of a
/// `Data` blob serialised from `IdentityKeyPair.serialize()`. The Keychain
/// layer here doesn't change.
public final class KeychainIdentityStore: @unchecked Sendable {

    public enum Error: Swift.Error, Equatable, Sendable {
        case keychainStatus(OSStatus)
        case missing
    }

    public static let defaultService = "vbwd.meinchat.plus.identity"
    public static let defaultAccount = "v1"

    private let service: String
    private let account: String

    public init(service: String = defaultService, account: String = defaultAccount) {
        self.service = service
        self.account = account
    }

    /// Returns true when an identity is paired on this device.
    public var isPaired: Bool {
        (try? load()) != nil
    }

    /// Stores the device identity bytes, sealed by the device-only access
    /// control. Overwrites any prior value.
    public func set(_ bytes: Data) throws {
        var attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: bytes,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(attrs as CFDictionary)
        attrs.removeValue(forKey: kSecReturnData as String)
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.keychainStatus(status) }
    }

    /// Returns the stored identity bytes, or nil if none has been paired.
    public func load() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw Error.keychainStatus(status)
        }
        return data
    }

    /// Wipes the local identity — used by Settings → "Revoke this device".
    /// After deletion the next send will require a re-pair.
    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.keychainStatus(status)
        }
    }
}
