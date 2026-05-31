import Foundation
import MeinChatPlugin

/// Decision the composer needs to make at peer-selection time (S28.7 §4.6):
///
/// 1. **Ready** — secure messaging is paired AND the peer has at least one
///    active device key → composer is enabled, "secure" affordance shown.
/// 2. **Disabled (peer not paired)** — the peer has no device keys yet → composer
///    is disabled with a "peer can't receive secure messages yet" hint.
/// 3. **Disabled (we're not paired)** — the local user hasn't paired their own
///    device → composer is disabled with a "pair this device first" hint.
/// 4. **Optimistic enable on probe failure** — the capabilities probe transient
///    errored → enable optimistically so the send still attempts (the send
///    path's fail-closed guard catches downgrades anyway).
public enum ComposerPrecheckResult: Equatable, Sendable {
    case ready
    case localNotPaired
    case peerCannotReceive
    case probeFailedOptimistic(error: String)

    public var canCompose: Bool {
        switch self {
        case .ready, .probeFailedOptimistic: return true
        case .localNotPaired, .peerCannotReceive: return false
        }
    }
}

public final class ComposerPrecheck: @unchecked Sendable {
    private let secure: MeinChatSecureMessaging

    public init(secure: MeinChatSecureMessaging) {
        self.secure = secure
    }

    /// Runs the local-pair + peer-device probe and returns the composer's
    /// decision. Suitable to call from a SwiftUI `.task` on the conversation
    /// screen — cheap (one cached capability read + one HTTP call).
    public func check(peerUserId: String) async -> ComposerPrecheckResult {
        if await !secure.isReady {
            return .localNotPaired
        }
        do {
            if try await secure.peerCanReceiveE2E(userId: peerUserId) {
                return .ready
            }
            return .peerCannotReceive
        } catch {
            return .probeFailedOptimistic(error: String(describing: error))
        }
    }
}
