import Foundation
import MeinChatPlugin

/// Stub conformer for `MeinChatSecureMessaging` that throws on every send /
/// decrypt call. Lives here until `LibSignalClient` is vendored and the
/// real `SecureSendService` / `SecureReadService` (S28.7 §3.2-3.3) replace it.
///
/// **Fail-closed contract:** never returns plaintext for an `e2e_v1` row,
/// never silently downgrades. UI surfaces the `notReady` error as a
/// "Secure messaging not yet available on this build" banner.
public enum StubSecureMessagingError: Swift.Error, Equatable, Sendable {
    /// The Signal protocol layer isn't compiled into this build yet.
    case notReady
}

public final class StubSecureMessaging: MeinChatSecureMessaging, @unchecked Sendable {
    private let identity: KeychainIdentityStore

    public init(identity: KeychainIdentityStore) {
        self.identity = identity
    }

    public var isReady: Bool {
        // Only ever reports ready when a real identity + signal layer lands.
        // The Keychain identity alone is not enough — the session machinery
        // is what does the encryption.
        get async { false }
    }

    public func sendSecure(_ plaintext: String,
                           in conversation: Conversation) async throws -> ChatMessage {
        throw StubSecureMessagingError.notReady
    }

    public func sendSecureAttachment(imageData: Data, fileName: String, caption: String?,
                                     in conversation: Conversation) async throws -> ChatMessage {
        throw StubSecureMessagingError.notReady
    }

    public func decryptIncoming(_ message: ChatMessage) async throws -> String {
        throw StubSecureMessagingError.notReady
    }

    public func peerCanReceiveE2E(userId: String) async throws -> Bool {
        // Stub always reports false: even if the peer has devices, this
        // build can't encrypt — secure-send would just error out. Returning
        // false keeps the composer in plain-mode (correct UX) until the
        // real Signal layer lands.
        false
    }
}
