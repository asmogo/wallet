import Foundation

enum NFCNdefPayload: Equatable {
    case text(String)
    case cashuBinary(Data)
}

/// NFC Forum Type 4 / Numo wire protocol, shared with Android's NfcType4Tag.
/// Kept independent of CoreNFC so malformed and interrupted exchanges can be tested.
struct NFCType4Tag {
    static let maxMessageSize = 0x70ff
    static let aid: [UInt8] = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]
    static let capabilityContainer: [UInt8] = [
        0x00, 0x0F, 0x20, 0x00, 0x3B, 0x00, 0x34,
        0x04, 0x06, 0xE1, 0x04, 0x70, 0xFF, 0x00, 0x00
    ]
    private enum File { case none, cc, ndef }
    private var selected: File = .none
    private var applicationSelected = false
    private let requestFile: [UInt8]
    private var incoming = [UInt8](repeating: 0, count: maxMessageSize + 2)
    private var written = [Bool](repeating: false, count: maxMessageSize + 2)

    init(request: String) throws {
        requestFile = try NFCNdefCodec.textFile(request)
    }

    mutating func reset() {
        applicationSelected = false
        selected = .none
        resetIncoming()
    }

    mutating func process(_ command: Data) -> (response: Data, payload: NFCNdefPayload?) {
        let bytes = [UInt8](command)
        guard bytes.count >= 4 else { return reply(0x67, 0x00) }
        guard bytes[0] == 0 else { return reply(0x6E, 0x00) }
        if bytes[1] == 0xA4, bytes[2] == 0x04 {
            reset()
            guard bytes[3] == 0, bytes.count == 12 || bytes.count == 13,
                  bytes[4] == 7, Array(bytes[5..<12]) == Self.aid else {
                return reply(0x6A, 0x82)
            }
            applicationSelected = true
            return reply()
        }
        guard applicationSelected else { return reply(0x6A, 0x82) }
        switch bytes[1] {
        case 0xA4:
            selected = .none
            guard bytes.count == 7 || bytes.count == 8, bytes[2] == 0, bytes[3] == 0x0C,
                  bytes[4] == 2, bytes[5] == 0xE1 else { return reply(0x67, 0x00) }
            switch bytes[6] {
            case 0x03: selected = .cc
            case 0x04: selected = .ndef
            default: return reply(0x6A, 0x82)
            }
            return reply()
        case 0xB0:
            guard bytes.count == 5 else { return reply(0x67, 0x00) }
            guard selected != .none else { return reply(0x6A, 0x82) }
            let file = selected == .cc ? Self.capabilityContainer : requestFile
            let offset = Int(bytes[2]) << 8 | Int(bytes[3])
            let length = bytes[4] == 0 ? 256 : Int(bytes[4])
            guard offset <= file.count else { return reply(0x6B, 0x00) }
            return (Data(file[offset..<min(offset + length, file.count)]) + Data([0x90, 0x00]), nil)
        case 0xD6:
            guard selected == .ndef else { return reply(0x6A, 0x82) }
            guard bytes.count >= 5, bytes[4] > 0,
                  bytes.count == 5 + Int(bytes[4]) else { return reply(0x67, 0x00) }
            let offset = Int(bytes[2]) << 8 | Int(bytes[3])
            let length = Int(bytes[4])
            guard offset + length <= incoming.count else { return reply(0x6B, 0x00) }
            // Support both NLEN-first and zero-NLEN/body/final-NLEN writers.
            if offset == 0, length >= 2, bytes[5] == 0, bytes[6] == 0 {
                resetIncoming()
            }
            incoming.replaceSubrange(offset..<offset + length, with: bytes[5...])
            for index in offset..<offset + length { written[index] = true }
            guard written[0], written[1] else { return reply() }
            let expected = Int(incoming[0]) << 8 | Int(incoming[1])
            guard expected <= Self.maxMessageSize else {
                resetIncoming()
                return reply(0x6B, 0x00)
            }
            guard expected > 0, written[0..<expected + 2].allSatisfy({ $0 }) else { return reply() }
            let payload = NFCNdefCodec.parseFile(Array(incoming[0..<expected + 2]))
            resetIncoming()
            guard let payload else { return reply(0x6A, 0x80) }
            return (Data([0x90, 0x00]), payload)
        default:
            return reply(0x6D, 0x00)
        }
    }

    private mutating func resetIncoming() {
        incoming = .init(repeating: 0, count: Self.maxMessageSize + 2)
        written = .init(repeating: false, count: Self.maxMessageSize + 2)
    }

    private func reply(_ sw1: UInt8 = 0x90, _ sw2: UInt8 = 0) -> (Data, NFCNdefPayload?) {
        (Data([sw1, sw2]), nil)
    }
}

enum NFCNdefCodec {
    enum EncodingError: Error { case tooLarge }

    static func textFile(_ text: String) throws -> [UInt8] {
        let payload = [0x02, 0x65, 0x6E] + Array(text.utf8)
        guard payload.count + 7 <= NFCType4Tag.maxMessageSize else { throw EncodingError.tooLarge }
        let short = payload.count <= 255
        let length = UInt32(payload.count)
        var record: [UInt8] = short
            ? [0xD1, 1, UInt8(length), 0x54]
            : [0xC1, 1, UInt8(length >> 24), UInt8((length >> 16) & 255),
               UInt8((length >> 8) & 255), UInt8(length & 255), 0x54]
        record += payload
        return [UInt8(record.count >> 8), UInt8(record.count & 255)] + record
    }

    static func parseFile(_ file: [UInt8]) -> NFCNdefPayload? {
        guard file.count >= 5 else { return nil }
        let nlen = Int(file[0]) << 8 | Int(file[1])
        guard nlen > 0, nlen <= NFCType4Tag.maxMessageSize, nlen + 2 == file.count else { return nil }
        let record = Array(file.dropFirst(2))
        let header = record[0]
        // Exactly one complete record; no chunks or IDs.
        guard header & 0xC0 == 0xC0, header & 0x28 == 0 else { return nil }
        let typeLength = Int(record[1])
        let short = header & 0x10 != 0
        let start = short ? 3 : 6
        guard record.count >= start, typeLength > 0 else { return nil }
        let payloadLength = short ? Int(record[2]) : record[2..<6].reduce(0) { ($0 << 8) | Int($1) }
        guard start + typeLength + payloadLength == record.count else { return nil }
        let type = Array(record[start..<start + typeLength])
        let payload = Array(record.dropFirst(start + typeLength))
        if header & 7 == 2 {
            guard String(bytes: type, encoding: .ascii)?.lowercased() == "application/octet-stream",
                  !payload.isEmpty else { return nil }
            return .cashuBinary(Data(payload))
        }
        guard header & 7 == 1, type.count == 1, let status = payload.first else { return nil }
        switch type[0] {
        case 0x54:
            let textStart = 1 + Int(status & 0x3F)
            guard status & 0xC0 == 0, textStart <= payload.count,
                  let text = String(bytes: payload.dropFirst(textStart), encoding: .utf8) else { return nil }
            return .text(text)
        case 0x55:
            // Cashu URLs use an uncompressed scheme, or an HTTP(S) token URL.
            let prefixes: [UInt8: String] = [0: "", 1: "http://www.", 2: "https://www.", 3: "http://", 4: "https://"]
            guard let prefix = prefixes[status],
                  let text = String(bytes: payload.dropFirst(), encoding: .utf8) else { return nil }
            return .text(prefix + text)
        default: return nil
        }
    }
}
