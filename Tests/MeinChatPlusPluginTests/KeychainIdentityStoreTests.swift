import Testing
import Foundation
@testable import MeinChatPlusPlugin

/// Sprint S28.7 §4.7 — Keychain identity store specs. Uses isolated
/// (service, account) tuples so simulator runs don't clobber each other.
struct KeychainIdentityStoreTests {

    private func makeStore(suffix: String = UUID().uuidString) -> KeychainIdentityStore {
        KeychainIdentityStore(
            service: "test.meinchat.plus.identity.\(suffix)",
            account: "v1")
    }

    @Test
    func notPairedByDefault() throws {
        let store = makeStore()
        defer { try? store.clear() }
        #expect(store.isPaired == false)
        #expect(try store.load() == nil)
    }

    @Test
    func setThenLoadRoundtrip() throws {
        let store = makeStore()
        defer { try? store.clear() }
        let bytes = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        try store.set(bytes)
        #expect(store.isPaired)
        #expect(try store.load() == bytes)
    }

    @Test
    func setOverwritesExisting() throws {
        let store = makeStore()
        defer { try? store.clear() }
        try store.set(Data([0xAA, 0xBB]))
        try store.set(Data([0xCC, 0xDD]))
        #expect(try store.load() == Data([0xCC, 0xDD]))
    }

    @Test
    func clearMakesNotPaired() throws {
        let store = makeStore()
        try store.set(Data([0x01, 0x02]))
        #expect(store.isPaired)
        try store.clear()
        #expect(store.isPaired == false)
    }

    @Test
    func clearOnUnpairedIsNoop() throws {
        let store = makeStore()
        try store.clear()  // must not throw on missing
        try store.clear()  // idempotent
    }
}
