import Foundation
import VBWDCore

/// Manages the device's signed + one-time prekey pools against the backend
/// (S28.3b §2.2-2.5). The body of `generate*` methods lands once
/// `LibSignalClient` is vendored — for now they accept already-generated
/// public-key bytes from the caller, which keeps the wire contract testable
/// without the crypto dependency.
public protocol PrekeyServiceProtocol: Sendable {
    /// Uploads a freshly minted signed prekey. Rotates whatever was there.
    func publishSigned(_ key: SignedPrekey) async throws
    /// Tops up the one-time prekey pool with the supplied batch.
    func publishOneTimeBatch(_ keys: [OneTimePrekey]) async throws
    /// Returns the current pool status — used by Settings + refill cadence.
    func fetchStatus() async throws -> PrekeyStatus
    /// True when the one-time pool dropped below `low_water_mark` (or below
    /// 20% capacity when the server didn't supply a mark).
    func needsRefill() async throws -> Bool
}

public final class DefaultPrekeyService: PrekeyServiceProtocol, @unchecked Sendable {
    private let api: APIClient
    private let fallbackLowWaterFraction: Double

    public init(api: APIClient, fallbackLowWaterFraction: Double = 0.2) {
        self.api = api
        self.fallbackLowWaterFraction = fallbackLowWaterFraction
    }

    private struct SignedBody: Encodable {
        let id: Int
        let public_key: String
        let signature: String
    }
    private struct OneTimeBody: Encodable {
        let keys: [OneTimePrekey]
    }

    public func publishSigned(_ key: SignedPrekey) async throws {
        let _: EmptyResponse = try await api.post(
            MeinChatPlusEndpoints.signedPrekey,
            body: SignedBody(id: key.id, public_key: key.publicKey, signature: key.signature))
    }

    public func publishOneTimeBatch(_ keys: [OneTimePrekey]) async throws {
        guard !keys.isEmpty else { return }
        let _: EmptyResponse = try await api.post(
            MeinChatPlusEndpoints.oneTimePrekeys,
            body: OneTimeBody(keys: keys))
    }

    public func fetchStatus() async throws -> PrekeyStatus {
        try await api.get(MeinChatPlusEndpoints.prekeyStatus)
    }

    public func needsRefill() async throws -> Bool {
        let status = try await fetchStatus()
        if let mark = status.lowWaterMark {
            return status.oneTimeRemaining <= mark
        }
        let threshold = max(1, Int(Double(status.oneTimeCapacity) * fallbackLowWaterFraction))
        return status.oneTimeRemaining <= threshold
    }
}
