import Testing
import Foundation
@testable import MeinChatPlusPlugin

/// Sprint S28.7 §4.2 — Envelope pack/unpack round trips.
struct EnvelopeRoundTripTests {

    private func slot(_ deviceId: String, _ headerLen: Int = 16, _ ctLen: Int = 64) -> Envelope.Slot {
        Envelope.Slot(
            deviceId: deviceId,
            header: Data(repeating: 0xAB, count: headerLen),
            ciphertext: Data((0..<ctLen).map { UInt8(($0 * 7) % 251) })
        )
    }

    @Test
    func twoDeviceRoundTrip() throws {
        let env = Envelope(v: 1, perRecipient: [slot("dev-A"), slot("dev-B")])
        let bytes = EnvelopePacker.pack(env)
        let decoded = try EnvelopePacker.unpack(bytes)
        #expect(decoded == env)
    }

    @Test
    func emptyRecipientsRoundTrip() throws {
        let env = Envelope(v: 1, perRecipient: [])
        let bytes = EnvelopePacker.pack(env)
        let decoded = try EnvelopePacker.unpack(bytes)
        #expect(decoded == env)
    }

    @Test
    func largeCiphertextRoundTrip() throws {
        // Exercise the 16-bit length encoding path (> 255 bytes).
        let env = Envelope(v: 1, perRecipient: [slot("dev-A", 32, 1024)])
        let bytes = EnvelopePacker.pack(env)
        let decoded = try EnvelopePacker.unpack(bytes)
        #expect(decoded == env)
        #expect(decoded.perRecipient[0].ciphertext.count == 1024)
    }

    @Test
    func tamperedCiphertextByteAltersDecode() throws {
        let env = Envelope(v: 1, perRecipient: [slot("dev-A")])
        var bytes = EnvelopePacker.pack(env)
        bytes[bytes.count - 1] ^= 0xFF
        // CBOR structure is still valid → decode succeeds, but the
        // ciphertext bytes don't match → AEAD failure would surface
        // downstream in the Signal session. The packer itself doesn't
        // authenticate; it just transports.
        let decoded = try EnvelopePacker.unpack(bytes)
        #expect(decoded.perRecipient[0].ciphertext != env.perRecipient[0].ciphertext)
    }

    @Test
    func truncatedEnvelopeThrows() {
        let env = Envelope(v: 1, perRecipient: [slot("dev-A")])
        let bytes = EnvelopePacker.pack(env)
        let truncated = bytes.prefix(5)
        #expect(throws: EnvelopePacker.Error.self) {
            _ = try EnvelopePacker.unpack(Data(truncated))
        }
    }

    @Test
    func malformedHeaderThrows() {
        // Major type 7 (simple/float) — not in our subset.
        let bad = Data([0xE0])
        #expect(throws: EnvelopePacker.Error.self) {
            _ = try EnvelopePacker.unpack(bad)
        }
    }

    @Test
    func unknownTopLevelKeyIsTolerated() throws {
        // Pack manually with an extra key — round trip should ignore it.
        // We rebuild the top-level CBOR map with 3 entries: v, perRecipient, extra.
        var raw = Data()
        // map(3)
        raw.append(0xA3)
        // text "v"
        raw.append(0x61); raw.append(contentsOf: "v".utf8)
        // uint 1
        raw.append(0x01)
        // text "perRecipient"
        raw.append(0x6C); raw.append(contentsOf: "perRecipient".utf8)
        // array(0)
        raw.append(0x80)
        // text "extra"
        raw.append(0x65); raw.append(contentsOf: "extra".utf8)
        // uint 42 (skipped)
        raw.append(0x18); raw.append(42)

        let decoded = try EnvelopePacker.unpack(raw)
        #expect(decoded.v == 1)
        #expect(decoded.perRecipient.isEmpty)
    }
}
