import Foundation

/// Errors raised when the client demanded `accepted_protocols: ["e2e_v1"]`
/// but the backend response or peer state would silently fall back to plain.
///
/// **Fail-closed contract (S28.7 §3.4 / critical-review §C14):**
/// the secure send/read services throw rather than ever transmitting
/// plaintext for an `e2e_v1` conversation.
public enum E2eGuardError: Swift.Error, Equatable, Sendable {
    /// The server returned `protocol != "e2e_v1"` for a conversation we
    /// demanded encryption on. UI: warning sheet; conversation not persisted.
    case protocolDowngrade(serverProtocol: String)
    /// The peer has zero active device keys — there's no one to encrypt for.
    /// UI: composer disabled with a "Peer can't receive secure messages yet" hint.
    case noPeerDeviceKeys
    /// The local device's slot is missing from a received envelope (sender
    /// failed to fan out to us). Likely a bug; tests pin this.
    case noSlotForThisDevice
    /// Called the secure path on a conversation that's still plain — caller
    /// should route through plain meinchat instead.
    case conversationIsNotE2e
    /// Tried to decrypt a non-e2e row through the secure read path.
    case notAnE2eMessage
}

/// Single home for the `accepted_protocols=["e2e_v1"]` → response check.
/// Called from both `SecureSendService.startE2eConversation` and the
/// composer precheck (S28.7 §3.4) once those services are implemented.
public enum DowngradeGuard {
    /// Throws `protocolDowngrade` if `responseProtocol` is anything other
    /// than `"e2e_v1"` when the client demanded e2e.
    public static func assertE2e(_ responseProtocol: String) throws {
        guard responseProtocol == "e2e_v1" else {
            throw E2eGuardError.protocolDowngrade(serverProtocol: responseProtocol)
        }
    }
}
