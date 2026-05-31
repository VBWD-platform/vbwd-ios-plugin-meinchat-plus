import Foundation
import VBWDCore
import MeinChatPlugin
#if canImport(LibSignalClient)
import LibSignalClient

/// Real Signal-protocol implementation of the cross-plugin
/// `MeinChatSecureMessaging` contract (S28.7 §3.2-3.3). Replaces
/// `StubSecureMessaging` once `LibSignalClient` resolves.
///
/// Send flow (`sendSecure`):
///   1. Pull peer's devices via `/messaging/users/<id>/devices`.
///   2. Include sender's OWN active devices (own-device decrypt, §3.2).
///   3. For each addressed device: ensure a Signal session exists (build
///      from `PreKeyBundle` if not), encrypt the padded plaintext.
///   4. Pack slots via `EnvelopePacker` (CBOR).
///   5. POST `{"envelope_b64": "..."}` to `/messages`.
///
/// Read flow (`decryptIncoming`):
///   1. Unpack envelope.
///   2. Find own slot by local device id.
///   3. Decrypt via SignalMessage / PreKeySignalMessage (auto-detected
///      from the CiphertextMessage type byte).
///   4. Strip padding.
public final class SignalSecureMessaging: MeinChatSecureMessaging, @unchecked Sendable {

    public enum SecureError: Swift.Error, Equatable, Sendable {
        case notPaired
        case noPeerDevices
        case noSlotForThisDevice
        case missingSenderDevice
        case decryptFailed
    }

    private let api: APIClient
    private let stores: SignalProtocolStores
    private let devices: DeviceRegistryServiceProtocol
    private let pairing: SignalPairingService
    private let currentUserId: () -> String?

    public init(api: APIClient,
                stores: SignalProtocolStores,
                devices: DeviceRegistryServiceProtocol,
                pairing: SignalPairingService,
                currentUserId: @escaping () -> String?) {
        self.api = api
        self.stores = stores
        self.devices = devices
        self.pairing = pairing
        self.currentUserId = currentUserId
    }

    public var isReady: Bool {
        get async { stores.isPaired && pairing.localDeviceId != nil }
    }

    public func peerCanReceiveE2E(userId: String) async throws -> Bool {
        let peerDevices = try await devices.listPeerDevices(userId: userId)
        return !peerDevices.isEmpty
    }

    // MARK: - Send

    public func sendSecure(_ plaintext: String,
                           in conversation: Conversation) async throws -> ChatMessage {
        guard stores.isPaired, let localDeviceId = pairing.localDeviceId else {
            throw SecureError.notPaired
        }
        guard let peerUserId = conversation.peerUserId else {
            throw SecureError.noPeerDevices
        }

        let padded = Padding.padTo256(plaintext)
        let addressed = try await addressedDevices(peerUserId: peerUserId,
                                                   localDeviceId: localDeviceId)
        guard !addressed.isEmpty else { throw SecureError.noPeerDevices }

        var slots: [Envelope.Slot] = []
        slots.reserveCapacity(addressed.count)
        let ctx = NullContext()

        for device in addressed {
            let address = ProtocolAddress(name: device.userId,
                                          deviceId: deviceIdAsUInt32(device.id))
            try await ensureSession(for: device, address: address, context: ctx)
            let ciphertext = try signalEncrypt(message: Array(padded),
                                               for: address,
                                               sessionStore: stores,
                                               identityStore: stores,
                                               context: ctx)
            slots.append(Envelope.Slot(
                deviceId: device.id,
                header: Data([UInt8(ciphertext.messageType.rawValue)]),
                ciphertext: Data(ciphertext.serialize())))
        }

        let envelope = Envelope(v: 1, perRecipient: slots)
        let envelopeBytes = EnvelopePacker.pack(envelope)
        let body = SecureMessageBody(envelopeB64: envelopeBytes.base64EncodedString(),
                                     senderDeviceId: localDeviceId)
        let msg: ChatMessage = try await api.post(
            "/messaging/conversations/\(conversation.id)/messages",
            body: body)
        return msg
    }

    public func sendSecureAttachment(imageData: Data, fileName: String, caption: String?,
                                     in conversation: Conversation) async throws -> ChatMessage {
        // S28.4 attachment encryption ships in a follow-up; for now reject
        // explicitly so the fail-closed contract holds (no plaintext upload
        // for e2e_v1 conversations).
        throw SecureError.decryptFailed
    }

    // MARK: - Read

    public func decryptIncoming(_ message: ChatMessage) async throws -> String {
        guard stores.isPaired, let localDeviceId = pairing.localDeviceId else {
            throw SecureError.notPaired
        }
        guard let envelopeB64 = message.envelopeB64,
              let envelopeData = Data(base64Encoded: envelopeB64) else {
            throw SecureError.decryptFailed
        }
        let envelope = try EnvelopePacker.unpack(envelopeData)
        guard let slot = envelope.perRecipient.first(where: { $0.deviceId == localDeviceId }) else {
            throw SecureError.noSlotForThisDevice
        }
        guard let senderUser = message.senderId,
              let senderDevice = message.senderDeviceId else {
            throw SecureError.missingSenderDevice
        }

        let address = ProtocolAddress(name: senderUser,
                                      deviceId: deviceIdAsUInt32(senderDevice))
        let ctx = NullContext()

        // The first byte of header is the CiphertextMessage type. Branch
        // between PreKeySignalMessage (initial contact) and SignalMessage
        // (established session).
        let typeByte = slot.header.first ?? 0
        let padded: [UInt8]
        if typeByte == CiphertextMessage.MessageType.preKey.rawValue {
            let prekeyMsg = try PreKeySignalMessage(bytes: Array(slot.ciphertext))
            padded = try signalDecryptPreKey(message: prekeyMsg,
                                             from: address,
                                             sessionStore: stores,
                                             identityStore: stores,
                                             preKeyStore: stores,
                                             signedPreKeyStore: stores,
                                             context: ctx)
        } else {
            let sigMsg = try SignalMessage(bytes: Array(slot.ciphertext))
            padded = try signalDecrypt(message: sigMsg,
                                       from: address,
                                       sessionStore: stores,
                                       identityStore: stores,
                                       context: ctx)
        }
        return try Padding.strip(Data(padded))
    }

    // MARK: - Internals

    /// Build the addressed-device list: peer's devices + sender's own
    /// active devices (excluding this one — we don't need to encrypt for
    /// the device that's sending).
    private func addressedDevices(peerUserId: String,
                                  localDeviceId: String) async throws -> [DeviceDescriptor] {
        async let peer = devices.listPeerDevices(userId: peerUserId)
        var addressed = try await peer
        if let mine = currentUserId() {
            async let ownTask = devices.listPeerDevices(userId: mine)
            let own = (try? await ownTask) ?? []
            for d in own where d.id != localDeviceId {
                addressed.append(d)
            }
        }
        return addressed
    }

    /// If we don't have a session with `address`, fetch the prekey bundle
    /// and build one. Subsequent calls are no-ops.
    private func ensureSession(for device: DeviceDescriptor,
                               address: ProtocolAddress,
                               context: NullContext) async throws {
        if try stores.loadSession(for: address, context: context) != nil {
            return
        }
        let wire = try await devices.fetchBundle(userId: device.userId,
                                                 deviceId: device.id)
        let bundle = try Self.makeBundle(from: wire, deviceId: address.deviceId)
        try processPreKeyBundle(bundle,
                                for: address,
                                sessionStore: stores,
                                identityStore: stores,
                                context: context)
    }

    private static func makeBundle(from wire: PrekeyBundle,
                                   deviceId: UInt32) throws -> PreKeyBundle {
        guard let identityBytes = Data(base64Encoded: wire.identityKey),
              let signedKeyBytes = Data(base64Encoded: wire.signedPrekey.publicKey),
              let signatureBytes = Data(base64Encoded: wire.signedPrekey.signature) else {
            throw SecureError.decryptFailed
        }
        let identityPub = try PublicKey(Array(identityBytes))
        let signedPub   = try PublicKey(Array(signedKeyBytes))
        let signedId    = UInt32(wire.signedPrekey.id)

        var oneTimeId: UInt32 = 0
        var oneTimePub: PublicKey?
        if let ot = wire.oneTimePrekey,
           let bytes = Data(base64Encoded: ot.publicKey) {
            oneTimeId = UInt32(ot.id)
            oneTimePub = try PublicKey(Array(bytes))
        }

        // Registration id we don't know — pass a placeholder; LibSignal
        // doesn't validate it against the peer's identity for the bundle
        // build, only stores it for later session derivation. Servers
        // could return it as a separate field in the future.
        return try PreKeyBundle(
            registrationId: 0,
            deviceId: deviceId,
            prekeyId: oneTimeId,
            prekey: oneTimePub,
            signedPrekeyId: signedId,
            signedPrekey: signedPub,
            signedPrekeySignature: Array(signatureBytes),
            identity: IdentityKey(publicKey: identityPub))
    }

    /// Backend device ids are UUID strings; LibSignal sessions key
    /// addresses by `(name: userId, deviceId: UInt32)`. We hash the UUID
    /// to a stable 32-bit value. The server-side counterpart does the
    /// same so peer addresses match. The mapping is irrelevant for
    /// over-the-wire correctness — slots are keyed by the raw UUID
    /// string via `Envelope.Slot.deviceId`.
    private func deviceIdAsUInt32(_ id: String) -> UInt32 {
        var hash: UInt32 = 5381
        for byte in id.utf8 {
            hash = (hash &* 33) &+ UInt32(byte)
        }
        return hash | 1   // never zero; some Signal callsites treat 0 as sentinel
    }
}

/// Wire body for `POST /messages` on `e2e_v1` conversations. Mirrors the
/// shape `vbwd-fe-user` sends.
private struct SecureMessageBody: Encodable {
    let envelope_b64: String
    let sender_device_id: String

    init(envelopeB64: String, senderDeviceId: String) {
        self.envelope_b64 = envelopeB64
        self.sender_device_id = senderDeviceId
    }
}

#endif
