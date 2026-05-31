import Testing
@testable import MeinChatPlusPlugin

/// Sprint S28.7 §4.4 — Fail-closed downgrade guard. The body that consumes
/// this guard (`SecureSendService.startE2eConversation`) ships once
/// `LibSignalClient` is vendored, but the pure error contract is fixed now
/// so the sprint's wire contract has a stable home.
struct DowngradeGuardTests {

    @Test
    func acceptsE2eV1() throws {
        try DowngradeGuard.assertE2e("e2e_v1")
    }

    @Test
    func rejectsPlain() {
        #expect(throws: E2eGuardError.protocolDowngrade(serverProtocol: "plain")) {
            try DowngradeGuard.assertE2e("plain")
        }
    }

    @Test
    func rejectsUnknownProtocol() {
        #expect(throws: E2eGuardError.protocolDowngrade(serverProtocol: "e2e_v2")) {
            try DowngradeGuard.assertE2e("e2e_v2")
        }
    }

    @Test
    func rejectsEmpty() {
        #expect(throws: E2eGuardError.protocolDowngrade(serverProtocol: "")) {
            try DowngradeGuard.assertE2e("")
        }
    }
}
