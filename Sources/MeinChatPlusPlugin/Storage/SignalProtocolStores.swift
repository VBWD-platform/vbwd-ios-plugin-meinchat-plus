import Foundation
#if canImport(LibSignalClient)
import LibSignalClient

/// In-process implementation of the four Signal Protocol stores
/// (`IdentityKeyStore`, `SessionStore`, `PreKeyStore`,
/// `SignedPreKeyStore`). Persistence:
///
/// - The local `IdentityKeyPair` private bytes live in Keychain via
///   `KeychainIdentityStore` (the only long-term secret on the device,
///   protected by `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
/// - Local `registrationId`, peer-identity trust map, session records,
///   prekey records, and signed-prekey records live in a CoreData /
///   UserDefaults-backed dictionary keyed by the serialised entity. For
///   simplicity we use UserDefaults (Data values), which is sufficient
///   for the chat volumes the v1 build targets. Switching to CoreData is
///   a contained refactor that doesn't change the protocol surface.
///
/// **Concurrency**: protected by an internal serial `DispatchQueue`. The
/// Signal libraries call these methods from background threads.
public final class SignalProtocolStores: IdentityKeyStore, SessionStore, PreKeyStore, SignedPreKeyStore, @unchecked Sendable {

    private let identity: KeychainIdentityStore
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "vbwd.meinchat.plus.signal.stores")

    // UserDefaults keys
    private let kRegistrationId = "meinchat.plus.signal.registrationId"
    private let kIdentityPub    = "meinchat.plus.signal.identityPub"
    private let kSessions       = "meinchat.plus.signal.sessions"        // [addressKey: Data]
    private let kPreKeys        = "meinchat.plus.signal.preKeys"         // [id: Data]
    private let kSignedPreKeys  = "meinchat.plus.signal.signedPreKeys"   // [id: Data]
    private let kTrust          = "meinchat.plus.signal.trust"           // [addressKey: Data]

    public init(identity: KeychainIdentityStore = KeychainIdentityStore(),
                defaults: UserDefaults = .standard) {
        self.identity = identity
        self.defaults = defaults
    }

    // MARK: - Public bootstrap helpers (called from PairingService)

    /// Persists the freshly generated local identity. Idempotent on the
    /// public bytes — overwrites the registration id only if not set.
    public func bootstrap(identityKeyPair: IdentityKeyPair, registrationId: UInt32) throws {
        try identity.set(Data(identityKeyPair.serialize()))
        try queue.sync {
            defaults.set(NSNumber(value: registrationId), forKey: kRegistrationId)
            defaults.set(Data(identityKeyPair.identityKey.publicKey.serialize()),
                         forKey: kIdentityPub)
        }
    }

    public var isPaired: Bool {
        identity.isPaired && registrationIdOrNil != nil
    }

    private var registrationIdOrNil: UInt32? {
        (defaults.object(forKey: kRegistrationId) as? NSNumber)?.uint32Value
    }

    // MARK: - IdentityKeyStore

    public func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        guard let bytes = try identity.load() else {
            throw SignalStoreError.identityNotPaired
        }
        return try IdentityKeyPair(bytes: Array(bytes))
    }

    public func localRegistrationId(context: StoreContext) throws -> UInt32 {
        guard let id = registrationIdOrNil else {
            throw SignalStoreError.identityNotPaired
        }
        return id
    }

    @discardableResult
    public func saveIdentity(_ identity: IdentityKey,
                             for address: ProtocolAddress,
                             context: StoreContext) throws -> Bool {
        let key = Self.addressKey(address)
        return queue.sync {
            var map = (defaults.dictionary(forKey: kTrust) as? [String: Data]) ?? [:]
            let bytes = Data(identity.publicKey.serialize())
            let previous = map[key]
            map[key] = bytes
            defaults.set(map, forKey: kTrust)
            // Return value semantics: true if an existing identity was
            // replaced (caller may decide to warn the user).
            return previous != nil && previous != bytes
        }
    }

    public func isTrustedIdentity(_ identity: IdentityKey,
                                  for address: ProtocolAddress,
                                  direction: Direction,
                                  context: StoreContext) throws -> Bool {
        let key = Self.addressKey(address)
        return queue.sync {
            let map = (defaults.dictionary(forKey: kTrust) as? [String: Data]) ?? [:]
            guard let stored = map[key] else {
                return true  // Trust on first use (TOFU).
            }
            return stored == Data(identity.publicKey.serialize())
        }
    }

    public func identity(for address: ProtocolAddress,
                         context: StoreContext) throws -> IdentityKey? {
        let key = Self.addressKey(address)
        return try queue.sync {
            let map = (defaults.dictionary(forKey: kTrust) as? [String: Data]) ?? [:]
            guard let bytes = map[key] else { return nil }
            let pub = try PublicKey(Array(bytes))
            return IdentityKey(publicKey: pub)
        }
    }

    // MARK: - SessionStore

    public func loadSession(for address: ProtocolAddress,
                            context: StoreContext) throws -> SessionRecord? {
        let key = Self.addressKey(address)
        return try queue.sync {
            let map = (defaults.dictionary(forKey: kSessions) as? [String: Data]) ?? [:]
            guard let bytes = map[key] else { return nil }
            return try SessionRecord(bytes: Array(bytes))
        }
    }

    public func loadExistingSessions(for addresses: [ProtocolAddress],
                                     context: StoreContext) throws -> [SessionRecord] {
        try addresses.compactMap { try loadSession(for: $0, context: context) }
    }

    public func storeSession(_ record: SessionRecord,
                             for address: ProtocolAddress,
                             context: StoreContext) throws {
        let key = Self.addressKey(address)
        queue.sync {
            var map = (defaults.dictionary(forKey: kSessions) as? [String: Data]) ?? [:]
            map[key] = Data(record.serialize())
            defaults.set(map, forKey: kSessions)
        }
    }

    // MARK: - PreKeyStore

    public func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        try queue.sync {
            let map = (defaults.dictionary(forKey: kPreKeys) as? [String: Data]) ?? [:]
            guard let bytes = map[String(id)] else {
                throw SignalStoreError.preKeyMissing(id)
            }
            return try PreKeyRecord(bytes: Array(bytes))
        }
    }

    public func storePreKey(_ record: PreKeyRecord,
                            id: UInt32,
                            context: StoreContext) throws {
        queue.sync {
            var map = (defaults.dictionary(forKey: kPreKeys) as? [String: Data]) ?? [:]
            map[String(id)] = Data(record.serialize())
            defaults.set(map, forKey: kPreKeys)
        }
    }

    public func removePreKey(id: UInt32, context: StoreContext) throws {
        queue.sync {
            var map = (defaults.dictionary(forKey: kPreKeys) as? [String: Data]) ?? [:]
            map.removeValue(forKey: String(id))
            defaults.set(map, forKey: kPreKeys)
        }
    }

    // MARK: - SignedPreKeyStore

    public func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        try queue.sync {
            let map = (defaults.dictionary(forKey: kSignedPreKeys) as? [String: Data]) ?? [:]
            guard let bytes = map[String(id)] else {
                throw SignalStoreError.signedPreKeyMissing(id)
            }
            return try SignedPreKeyRecord(bytes: Array(bytes))
        }
    }

    public func storeSignedPreKey(_ record: SignedPreKeyRecord,
                                  id: UInt32,
                                  context: StoreContext) throws {
        queue.sync {
            var map = (defaults.dictionary(forKey: kSignedPreKeys) as? [String: Data]) ?? [:]
            map[String(id)] = Data(record.serialize())
            defaults.set(map, forKey: kSignedPreKeys)
        }
    }

    // MARK: - Wipe (Settings → Revoke device)

    /// Wipes ALL state so the next pairing starts clean. Caller is
    /// responsible for the server-side `DELETE /me/devices/<id>` call.
    public func wipe() throws {
        try identity.clear()
        queue.sync {
            for key in [kRegistrationId, kIdentityPub, kSessions, kPreKeys, kSignedPreKeys, kTrust] {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Helpers

    private static func addressKey(_ address: ProtocolAddress) -> String {
        "\(address.name).\(address.deviceId)"
    }
}

public enum SignalStoreError: Swift.Error, Equatable, Sendable {
    case identityNotPaired
    case preKeyMissing(UInt32)
    case signedPreKeyMissing(UInt32)
}

#endif
