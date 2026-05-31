import Testing
import Foundation
@testable import MeinChatPlusPlugin

/// Sprint S28.7 §4.6 — Composer precheck specs.
struct ComposerPrecheckTests {

    @Test
    func readyWhenPairedAndPeerHasKeys() async {
        let fake = FakeSecureMessaging()
        fake.ready = true
        fake.peerHasKeys = true
        let pre = ComposerPrecheck(secure: fake)
        let r = await pre.check(peerUserId: "u-peer")
        #expect(r == .ready)
        #expect(r.canCompose)
    }

    @Test
    func disabledWhenLocalNotPaired() async {
        let fake = FakeSecureMessaging()
        fake.ready = false
        fake.peerHasKeys = true
        let pre = ComposerPrecheck(secure: fake)
        let r = await pre.check(peerUserId: "u-peer")
        #expect(r == .localNotPaired)
        #expect(!r.canCompose)
    }

    @Test
    func disabledWhenPeerHasNoKeys() async {
        let fake = FakeSecureMessaging()
        fake.ready = true
        fake.peerHasKeys = false
        let pre = ComposerPrecheck(secure: fake)
        let r = await pre.check(peerUserId: "u-peer")
        #expect(r == .peerCannotReceive)
        #expect(!r.canCompose)
    }

    @Test
    func optimisticEnableOnProbeFailure() async {
        let fake = FakeSecureMessaging()
        fake.ready = true
        fake.peerProbeError = FakeError.transient
        let pre = ComposerPrecheck(secure: fake)
        let r = await pre.check(peerUserId: "u-peer")
        if case .probeFailedOptimistic = r {
            #expect(r.canCompose)
        } else {
            Issue.record("Expected .probeFailedOptimistic, got \(r)")
        }
    }
}
