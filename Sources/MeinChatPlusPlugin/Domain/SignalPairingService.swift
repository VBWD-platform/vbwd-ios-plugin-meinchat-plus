import Foundation
#if canImport(LibSignalClient)
import LibSignalClient

/// One-shot pairing flow (S28.7 §3.1):
///
/// 1. Generate `IdentityKeyPair`, a `SignedPreKeyRecord`, and 100
///    one-time `PreKeyRecord`s client-side.
/// 2. Persist private halves to the local Signal stores (which write the
///    identity bytes to Keychain).
/// 3. Upload public halves to the backend:
///       - `POST /me/devices`           (identity pubkey + label)
///       - `POST /me/prekeys/signed`    (signed prekey + signature)
///       - `POST /me/prekeys/one-time`  (batch of 100)
/// 4. Record the server-assigned `device_id` so subsequent envelopes can
///    address it.
///
/// Idempotent: re-running after a successful pair returns the cached
/// device id without re-uploading. To re-pair from scratch the caller
/// must first `wipeLocalIdentity()` (Settings → Revoke this device).
public final class SignalPairingService: @unchecked Sendable {

    public enum PairingError: Swift.Error, Equatable, Sendable {
        case alreadyPaired(deviceId: String)
        case backendRejected(message: String)
    }

    private let stores: SignalProtocolStores
    private let devices: DeviceRegistryServiceProtocol
    private let prekeys: PrekeyServiceProtocol
    private let defaults: UserDefaults
    private let kLocalDeviceId = "meinchat.plus.signal.localDeviceId"

    public init(stores: SignalProtocolStores,
                devices: DeviceRegistryServiceProtocol,
                prekeys: PrekeyServiceProtocol,
                defaults: UserDefaults = .standard) {
        self.stores = stores
        self.devices = devices
        self.prekeys = prekeys
        self.defaults = defaults
    }

    /// Server-assigned device id from a previous successful pair, if any.
    public var localDeviceId: String? {
        defaults.string(forKey: kLocalDeviceId)
    }

    /// Runs the full pairing flow. `label` is shown in Settings to
    /// identify this device.
    public func pair(label: String) async throws -> String {
        if let existing = localDeviceId, stores.isPaired {
            return existing
        }

        // 1. Mint local keys.
        let identityKeyPair = IdentityKeyPair.generate()
        let registrationId = UInt32.random(in: 1..<16384)  // 14-bit ids per Signal
        try stores.bootstrap(identityKeyPair: identityKeyPair,
                             registrationId: registrationId)

        // 2. Register the device. Identity pubkey is sent as base64 so the
        //    backend can store opaque bytes regardless of curve choice.
        let identityB64 = Data(identityKeyPair.identityKey.publicKey.serialize())
            .base64EncodedString()
        let device = try await devices.registerDevice(label: label,
                                                      identityKey: identityB64)
        defaults.set(device.id, forKey: kLocalDeviceId)

        // 3. Signed prekey + 100 one-time prekeys.
        try await uploadSignedPreKey(identityKeyPair: identityKeyPair)
        try await uploadOneTimePreKeys(count: 100)

        return device.id
    }

    /// Adds another batch of one-time prekeys (called by the refill task
    /// when the server's `low_water_mark` is reached).
    public func refillOneTimePreKeys(count: Int = 100) async throws {
        try await uploadOneTimePreKeys(count: count)
    }

    // MARK: - Internals

    private func uploadSignedPreKey(identityKeyPair: IdentityKeyPair) async throws {
        let id = UInt32.random(in: 1..<UInt32.max)
        let keyPair = PrivateKey.generate()
        let pubBytes = keyPair.publicKey.serialize()
        let signature = identityKeyPair.privateKey.generateSignature(message: pubBytes)
        let record = try SignedPreKeyRecord(
            id: id,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            privateKey: keyPair,
            signature: signature)
        try stores.storeSignedPreKey(record, id: id, context: NullContext())

        let wire = SignedPrekey(
            id: Int(id),
            publicKey: Data(pubBytes).base64EncodedString(),
            signature: Data(signature).base64EncodedString(),
            createdAt: nil)
        try await prekeys.publishSigned(wire)
    }

    private func uploadOneTimePreKeys(count: Int) async throws {
        var wire: [OneTimePrekey] = []
        wire.reserveCapacity(count)
        for _ in 0..<count {
            let id = UInt32.random(in: 1..<UInt32.max)
            let keyPair = PrivateKey.generate()
            let record = try PreKeyRecord(id: id, privateKey: keyPair)
            try stores.storePreKey(record, id: id, context: NullContext())
            wire.append(OneTimePrekey(
                id: Int(id),
                publicKey: Data(keyPair.publicKey.serialize()).base64EncodedString()))
        }
        try await prekeys.publishOneTimeBatch(wire)
    }
}

#endif
