import Foundation

/// Wire-format envelope for an `e2e_v1` ciphertext message (S28.3b §2.6).
/// One envelope carries one slot per addressed device — peer's devices plus
/// the sender's own active devices (own-device decrypt — critical-review §C7).
public struct Envelope: Equatable, Sendable {
    public let v: Int
    public let perRecipient: [Slot]

    public struct Slot: Equatable, Sendable {
        public let deviceId: String
        public let header: Data
        public let ciphertext: Data

        public init(deviceId: String, header: Data, ciphertext: Data) {
            self.deviceId = deviceId
            self.header = header
            self.ciphertext = ciphertext
        }
    }

    public init(v: Int = 1, perRecipient: [Slot]) {
        self.v = v
        self.perRecipient = perRecipient
    }
}

/// Packs / unpacks `Envelope` to/from CBOR. Restricted CBOR grammar shared
/// with the server (`cbor2`) and web client (`cbor-x`):
///
///     Envelope = { "v": uint, "perRecipient": [Slot] }
///     Slot     = { "device_id": text, "header": bytes, "ciphertext": bytes }
///
/// Definite-length maps + arrays only; UTF-8 text keys + values; major types
/// 0 (uint), 2 (bytes), 3 (text), 4 (array), 5 (map). No tags, no floats.
/// This subset is small enough to implement directly without vendoring
/// SwiftCBOR (DRY across the three implementations).
public enum EnvelopePacker {

    public enum Error: Swift.Error, Equatable, Sendable {
        case truncated
        case unsupportedMajorType(UInt8)
        case unsupportedLengthEncoding(UInt8)
        case wrongType
        case missingKey(String)
        case keyNotText
        case lengthExceedsBuffer
    }

    // MARK: - Pack

    public static func pack(_ envelope: Envelope) -> Data {
        var out = Data()
        // Top-level map(2)
        out.append(cborMap(count: 2))
        out.append(cborText("v"))
        out.append(cborUInt(UInt64(envelope.v)))
        out.append(cborText("perRecipient"))
        out.append(cborArray(count: UInt64(envelope.perRecipient.count)))
        for slot in envelope.perRecipient {
            out.append(cborMap(count: 3))
            out.append(cborText("device_id"))
            out.append(cborText(slot.deviceId))
            out.append(cborText("header"))
            out.append(cborBytes(slot.header))
            out.append(cborText("ciphertext"))
            out.append(cborBytes(slot.ciphertext))
        }
        return out
    }

    // MARK: - Unpack

    public static func unpack(_ data: Data) throws -> Envelope {
        var cursor = Cursor(data)
        let top = try cursor.readMap()
        var version: Int?
        var slots: [Envelope.Slot] = []
        for _ in 0..<top {
            let key = try cursor.readText()
            switch key {
            case "v":
                version = Int(try cursor.readUInt())
            case "perRecipient":
                let arrayLen = try cursor.readArray()
                slots.reserveCapacity(Int(arrayLen))
                for _ in 0..<arrayLen {
                    slots.append(try readSlot(&cursor))
                }
            default:
                // Skip unknown top-level keys (forward compat).
                try cursor.skipOneValue()
            }
        }
        guard let v = version else { throw Error.missingKey("v") }
        return Envelope(v: v, perRecipient: slots)
    }

    private static func readSlot(_ cursor: inout Cursor) throws -> Envelope.Slot {
        let count = try cursor.readMap()
        var deviceId: String?
        var header: Data?
        var ciphertext: Data?
        for _ in 0..<count {
            let key = try cursor.readText()
            switch key {
            case "device_id":   deviceId = try cursor.readText()
            case "header":      header = try cursor.readBytes()
            case "ciphertext":  ciphertext = try cursor.readBytes()
            default:            try cursor.skipOneValue()
            }
        }
        guard let d = deviceId else { throw Error.missingKey("device_id") }
        guard let h = header else { throw Error.missingKey("header") }
        guard let c = ciphertext else { throw Error.missingKey("ciphertext") }
        return Envelope.Slot(deviceId: d, header: h, ciphertext: c)
    }

    // MARK: - CBOR header encoders

    private static func cborMap(count: UInt64) -> Data { typed(major: 5, value: count) }
    private static func cborArray(count: UInt64) -> Data { typed(major: 4, value: count) }
    private static func cborUInt(_ v: UInt64) -> Data { typed(major: 0, value: v) }

    private static func cborText(_ s: String) -> Data {
        let bytes = Data(s.utf8)
        return typed(major: 3, value: UInt64(bytes.count)) + bytes
    }

    private static func cborBytes(_ d: Data) -> Data {
        typed(major: 2, value: UInt64(d.count)) + d
    }

    /// Emits the CBOR initial byte + length bytes for a given major type
    /// and unsigned argument value, picking the smallest legal encoding.
    private static func typed(major: UInt8, value: UInt64) -> Data {
        let prefix: UInt8 = major << 5
        if value < 24 {
            return Data([prefix | UInt8(value)])
        }
        if value <= UInt64(UInt8.max) {
            return Data([prefix | 24, UInt8(value)])
        }
        if value <= UInt64(UInt16.max) {
            return Data([prefix | 25,
                         UInt8((value >> 8) & 0xff),
                         UInt8(value & 0xff)])
        }
        if value <= UInt64(UInt32.max) {
            return Data([prefix | 26,
                         UInt8((value >> 24) & 0xff),
                         UInt8((value >> 16) & 0xff),
                         UInt8((value >> 8) & 0xff),
                         UInt8(value & 0xff)])
        }
        var bytes: [UInt8] = [prefix | 27]
        for i in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((value >> i) & 0xff))
        }
        return Data(bytes)
    }
}

// MARK: - Decoder cursor

private struct Cursor {
    private let data: Data
    private var index: Int

    init(_ data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    mutating func readByte() throws -> UInt8 {
        guard index < data.endIndex else { throw EnvelopePacker.Error.truncated }
        let b = data[index]
        index += 1
        return b
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, index + count <= data.endIndex else {
            throw EnvelopePacker.Error.lengthExceedsBuffer
        }
        let slice = data[index..<(index + count)]
        index += count
        return Data(slice)
    }

    /// Reads (major, argument) where argument is the unsigned value the
    /// header encodes — the count for maps/arrays/byte-strings/text-strings,
    /// or the value itself for uint.
    mutating func readHeader() throws -> (major: UInt8, argument: UInt64) {
        let b = try readByte()
        let major = b >> 5
        let additional = b & 0x1f
        let arg: UInt64
        switch additional {
        case 0...23:
            arg = UInt64(additional)
        case 24:
            arg = UInt64(try readByte())
        case 25:
            let hi = UInt64(try readByte())
            let lo = UInt64(try readByte())
            arg = (hi << 8) | lo
        case 26:
            var v: UInt64 = 0
            for _ in 0..<4 { v = (v << 8) | UInt64(try readByte()) }
            arg = v
        case 27:
            var v: UInt64 = 0
            for _ in 0..<8 { v = (v << 8) | UInt64(try readByte()) }
            arg = v
        default:
            throw EnvelopePacker.Error.unsupportedLengthEncoding(additional)
        }
        return (major, arg)
    }

    mutating func readMap() throws -> UInt64 {
        let (m, c) = try readHeader()
        guard m == 5 else { throw EnvelopePacker.Error.wrongType }
        return c
    }
    mutating func readArray() throws -> UInt64 {
        let (m, c) = try readHeader()
        guard m == 4 else { throw EnvelopePacker.Error.wrongType }
        return c
    }
    mutating func readUInt() throws -> UInt64 {
        let (m, c) = try readHeader()
        guard m == 0 else { throw EnvelopePacker.Error.wrongType }
        return c
    }
    mutating func readBytes() throws -> Data {
        let (m, c) = try readHeader()
        guard m == 2 else { throw EnvelopePacker.Error.wrongType }
        return try readBytes(Int(c))
    }
    mutating func readText() throws -> String {
        let (m, c) = try readHeader()
        guard m == 3 else { throw EnvelopePacker.Error.keyNotText }
        let raw = try readBytes(Int(c))
        return String(decoding: raw, as: UTF8.self)
    }

    /// Skips one whole value (used for unknown map keys to keep forward compat).
    mutating func skipOneValue() throws {
        let (m, c) = try readHeader()
        switch m {
        case 0, 1:
            return  // uint / negint — no extra bytes after the header
        case 2, 3:
            _ = try readBytes(Int(c))
        case 4:
            for _ in 0..<c { try skipOneValue() }
        case 5:
            for _ in 0..<(c * 2) { try skipOneValue() }
        default:
            throw EnvelopePacker.Error.unsupportedMajorType(m)
        }
    }
}
