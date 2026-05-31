import Foundation

/// One device registered to a user (S28.3b §2.1). The server exposes the
/// public identity key here; private bytes live in the device's Keychain.
public struct DeviceDescriptor: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let userId: String
    public let label: String?
    /// Hex- or base64-encoded depending on backend choice. Treated opaquely
    /// by the client — passed straight to LibSignalClient as bytes.
    public let identityKey: String
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, label
        case userId = "user_id"
        case identityKey = "identity_key"
        case createdAt = "created_at"
    }

    public init(id: String, userId: String, label: String?,
                identityKey: String, createdAt: String?) {
        self.id = id
        self.userId = userId
        self.label = label
        self.identityKey = identityKey
        self.createdAt = createdAt
    }
}

/// Signed prekey (S28.3b §2.2). One per device, rotated on schedule.
public struct SignedPrekey: Codable, Equatable, Sendable {
    public let id: Int
    public let publicKey: String
    public let signature: String
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, signature
        case publicKey = "public_key"
        case createdAt = "created_at"
    }
}

/// One-time prekey (S28.3b §2.3). Consumed under
/// `SELECT … FOR UPDATE SKIP LOCKED` on the server, so first-contact
/// races yield distinct prekeys (critical-review §C5).
public struct OneTimePrekey: Codable, Equatable, Sendable {
    public let id: Int
    public let publicKey: String

    enum CodingKeys: String, CodingKey {
        case id
        case publicKey = "public_key"
    }
}

/// Bundle returned by `GET /messaging/users/<user>/devices/<dev>/bundle` —
/// everything a sender needs to initiate an X3DH handshake with a peer device.
public struct PrekeyBundle: Codable, Equatable, Sendable {
    public let deviceId: String
    public let identityKey: String
    public let signedPrekey: SignedPrekey
    /// May be nil when the peer's one-time prekey pool is exhausted; X3DH
    /// still works without it but loses one-shot replay protection.
    public let oneTimePrekey: OneTimePrekey?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case identityKey = "identity_key"
        case signedPrekey = "signed_prekey"
        case oneTimePrekey = "one_time_prekey"
    }
}

/// Response of `GET /me/prekeys/status` (S28.3b §2.5). Drives the
/// settings UI's "97 of 100 remaining" row + the auto-refill cadence.
public struct PrekeyStatus: Codable, Equatable, Sendable {
    public let oneTimeRemaining: Int
    public let oneTimeCapacity: Int
    public let signedRotatedAt: String?
    public let lowWaterMark: Int?

    enum CodingKeys: String, CodingKey {
        case oneTimeRemaining = "one_time_remaining"
        case oneTimeCapacity = "one_time_capacity"
        case signedRotatedAt = "signed_rotated_at"
        case lowWaterMark = "low_water_mark"
    }
}
