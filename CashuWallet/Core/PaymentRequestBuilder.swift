import Foundation

enum PaymentRequestBuilder {
    enum BuildError: Error {
        case invalidPubkeyHex
        case nprofileEncodeFailed
    }

    /// Build a NUT-18 creqA-encoded payment request.
    /// Wire format: "creqA" + base64url(no padding)(CBOR(payload)).
    static func build(
        id: String,
        amount: UInt64?,
        unit: String?,
        singleUse: Bool? = nil,
        mints: [String],
        description: String?,
        nostrPubkeyHex: String,
        relays: [String],
        nip: String = "17"
    ) throws -> String {
        let nprofile = try makeNprofile(pubkeyHex: nostrPubkeyHex, relays: relays)

        var transport: [(Nut18Key, Nut18Value)] = []
        transport.append((.text("t"), .text("nostr")))
        transport.append((.text("a"), .text(nprofile)))
        transport.append((.text("g"), .array([
            .array([.text("n"), .text(nip)])
        ])))

        var request: [(Nut18Key, Nut18Value)] = []
        request.append((.text("i"), .text(id)))
        if let amount, amount > 0 {
            request.append((.text("a"), .uint(amount)))
        }
        if let unit, !unit.isEmpty {
            request.append((.text("u"), .text(unit)))
        }
        if let singleUse {
            request.append((.text("s"), .bool(singleUse)))
        }
        if !mints.isEmpty {
            request.append((.text("m"), .array(mints.map { .text($0) })))
        }
        if let description, !description.isEmpty {
            request.append((.text("d"), .text(description)))
        }
        request.append((.text("t"), .array([.map(transport)])))

        let cbor = Nut18CBOR.encode(.map(request))
        return "creqA" + Base64URL.encode(cbor)
    }

    /// Encode a NIP-19 nprofile: bech32(hrp="nprofile", TLV(pubkey, relays...))
    static func makeNprofile(pubkeyHex: String, relays: [String]) throws -> String {
        guard let pubkeyBytes = Data(hex: pubkeyHex), pubkeyBytes.count == 32 else {
            throw BuildError.invalidPubkeyHex
        }
        var tlv = Data()
        // Type 0: pubkey (32 bytes)
        tlv.append(0x00)
        tlv.append(UInt8(pubkeyBytes.count))
        tlv.append(pubkeyBytes)
        // Type 1: relay URL (utf-8)
        for relay in relays {
            let bytes = Array(relay.utf8)
            guard bytes.count <= 255 else { continue }
            tlv.append(0x01)
            tlv.append(UInt8(bytes.count))
            tlv.append(contentsOf: bytes)
        }
        do {
            return try Bech32.encode(hrp: "nprofile", data: tlv)
        } catch {
            throw BuildError.nprofileEncodeFailed
        }
    }
}

// MARK: - Hex helper

extension Data {
    init?(hex: String) {
        let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes = Data()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = bytes
    }
}

// MARK: - Minimal CBOR (RFC 8949 — definite-length subset)

enum Nut18Key {
    case text(String)
}

indirect enum Nut18Value {
    case text(String)
    case uint(UInt64)
    case bool(Bool)
    case array([Nut18Value])
    case map([(Nut18Key, Nut18Value)])
}

enum Nut18CBOR {
    static func encode(_ value: Nut18Value) -> Data {
        var out = Data()
        encodeInto(value, &out)
        return out
    }

    private static func encodeInto(_ value: Nut18Value, _ out: inout Data) {
        switch value {
        case .text(let s):
            let bytes = Array(s.utf8)
            writeHeader(majorType: 3, length: UInt64(bytes.count), into: &out)
            out.append(contentsOf: bytes)
        case .uint(let n):
            writeHeader(majorType: 0, length: n, into: &out)
        case .bool(let b):
            out.append(b ? 0xF5 : 0xF4)
        case .array(let items):
            writeHeader(majorType: 4, length: UInt64(items.count), into: &out)
            for item in items { encodeInto(item, &out) }
        case .map(let pairs):
            writeHeader(majorType: 5, length: UInt64(pairs.count), into: &out)
            for (k, v) in pairs {
                if case .text(let s) = k {
                    encodeInto(.text(s), &out)
                }
                encodeInto(v, &out)
            }
        }
    }

    private static func writeHeader(majorType: UInt8, length: UInt64, into out: inout Data) {
        let m = majorType << 5
        if length < 24 {
            out.append(m | UInt8(length))
        } else if length < 0x100 {
            out.append(m | 24)
            out.append(UInt8(length))
        } else if length < 0x10000 {
            out.append(m | 25)
            out.append(UInt8(length >> 8))
            out.append(UInt8(length & 0xFF))
        } else if length < 0x100000000 {
            out.append(m | 26)
            for shift in stride(from: 24, through: 0, by: -8) {
                out.append(UInt8((length >> shift) & 0xFF))
            }
        } else {
            out.append(m | 27)
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8((length >> shift) & 0xFF))
            }
        }
    }
}

// MARK: - Base64URL (no padding)

enum Base64URL {
    static func encode(_ data: Data) -> String {
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        while s.hasSuffix("=") { s.removeLast() }
        return s
    }

    static func decode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
        t = t.replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t.append("=") }
        return Data(base64Encoded: t)
    }
}
