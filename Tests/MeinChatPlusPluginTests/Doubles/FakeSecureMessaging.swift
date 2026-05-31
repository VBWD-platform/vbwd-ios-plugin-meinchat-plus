import Foundation
@testable import MeinChatPlusPlugin
import MeinChatPlugin

/// Test double for the cross-plugin `MeinChatSecureMessaging` contract.
final class FakeSecureMessaging: MeinChatSecureMessaging, @unchecked Sendable {
    var ready: Bool = false
    var peerHasKeys: Bool = false
    var peerProbeError: Error?

    var isReady: Bool {
        get async { ready }
    }

    func sendSecure(_ plaintext: String, in conversation: Conversation) async throws -> ChatMessage {
        fatalError("not used in these tests")
    }

    func sendSecureAttachment(imageData: Data, fileName: String, caption: String?,
                              in conversation: Conversation) async throws -> ChatMessage {
        fatalError("not used in these tests")
    }

    func decryptIncoming(_ message: ChatMessage) async throws -> String {
        fatalError("not used in these tests")
    }

    func peerCanReceiveE2E(userId: String) async throws -> Bool {
        if let err = peerProbeError { throw err }
        return peerHasKeys
    }
}

enum FakeError: Error, Equatable { case transient }
