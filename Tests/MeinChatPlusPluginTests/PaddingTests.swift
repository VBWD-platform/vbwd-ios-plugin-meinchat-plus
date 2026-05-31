import Testing
import Foundation
@testable import MeinChatPlusPlugin

/// Sprint S28.7 §4.1 — Padding specs.
struct PaddingTests {

    @Test
    func padThenStripRecoversOriginal() throws {
        for sample in ["hi", "hello world", String(repeating: "x", count: 1000), ""] {
            let padded = Padding.padTo256(sample)
            let recovered = try Padding.strip(padded)
            #expect(recovered == sample)
        }
    }

    @Test
    func paddedLengthIsMultipleOf256() {
        for length in [0, 1, 10, 100, 255, 256, 257, 512, 999] {
            let payload = Data(repeating: 0x41, count: length)  // 'A'
            let padded = Padding.pad(payload)
            #expect(padded.count % 256 == 0,
                    "length=\(length) → padded=\(padded.count)")
        }
    }

    @Test
    func minimumPaddedLengthIs256() {
        // Empty input still hits the 256-byte floor.
        let padded = Padding.pad(Data())
        #expect(padded.count == 256)
    }

    @Test
    func paddingIsNonDeterministic() {
        // Same input twice → identical header + body, different tails.
        let a = Padding.padTo256("hello")
        let b = Padding.padTo256("hello")
        #expect(a.count == b.count)
        #expect(a != b, "Padding tail must be random, not deterministic.")
    }

    @Test
    func truncatedHeaderThrows() {
        #expect(throws: Padding.Error.self) {
            _ = try Padding.strip(Data([0x00, 0x01]))  // 2 bytes < 4-byte header
        }
    }

    @Test
    func lengthExceedingBufferThrows() {
        // Header claims 10_000 bytes but buffer is 256.
        var bytes = Data(count: 256)
        var len = UInt32(10_000).bigEndian
        withUnsafeBytes(of: &len) { ptr in
            for i in 0..<4 { bytes[i] = ptr[i] }
        }
        #expect(throws: Padding.Error.self) {
            _ = try Padding.strip(bytes)
        }
    }
}
