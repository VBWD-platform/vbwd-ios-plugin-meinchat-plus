import Foundation
import CryptoKit

/// 256-byte-multiple plaintext padding (S28.7 §3.2 / S28 strategy §1.5).
/// Encrypted-message observer learns the original length only to within
/// ± 256 bytes.
///
/// Layout of the padded buffer:
///
///     [ 4-byte big-endian payload length ][ payload bytes ][ random tail ]
///
/// Total length is rounded UP to the next multiple of 256. Random-byte tail
/// (NOT zero-filled) defends against length-equality attacks on the padding
/// itself.
public enum Padding {

    /// Smallest block size the padded buffer is rounded to. S28 fixes this
    /// at 256 bytes — observers learn plaintext length only to that precision.
    public static let blockSize = 256

    public enum Error: Swift.Error, Equatable, Sendable {
        case truncatedHeader
        case lengthExceedsBuffer
    }

    /// Pads a UTF-8 string to a multiple of `blockSize` bytes.
    public static func padTo256(_ plaintext: String) -> Data {
        pad(Data(plaintext.utf8))
    }

    /// Pads arbitrary bytes to a multiple of `blockSize`.
    public static func pad(_ payload: Data) -> Data {
        let header = UInt32(payload.count).bigEndianData
        let body = header + payload
        let target = nextBlockBoundary(body.count)
        let tailLength = target - body.count
        return body + randomBytes(tailLength)
    }

    /// Strips padding written by `pad(_:)` and returns the original payload as a string.
    public static func strip(_ padded: Data) throws -> String {
        let bytes = try stripToBytes(padded)
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    /// Strips padding and returns the raw payload bytes.
    public static func stripToBytes(_ padded: Data) throws -> Data {
        guard padded.count >= 4 else { throw Error.truncatedHeader }
        let header = padded.prefix(4)
        let length = header.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(as: UInt32.self).bigEndian
        }
        let payloadStart = padded.startIndex.advanced(by: 4)
        let payloadEnd = payloadStart.advanced(by: Int(length))
        guard payloadEnd <= padded.endIndex else { throw Error.lengthExceedsBuffer }
        return padded[payloadStart..<payloadEnd]
    }

    // MARK: - Internals

    private static func nextBlockBoundary(_ size: Int) -> Int {
        let remainder = size % blockSize
        if remainder == 0 { return max(size, blockSize) }
        return size + (blockSize - remainder)
    }

    private static func randomBytes(_ count: Int) -> Data {
        guard count > 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

private extension UInt32 {
    var bigEndianData: Data {
        var be = self.bigEndian
        return Data(bytes: &be, count: MemoryLayout<UInt32>.size)
    }
}
