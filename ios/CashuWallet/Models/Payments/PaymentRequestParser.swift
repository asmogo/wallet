import Foundation
import Cdk
import CryptoKit

enum PaymentRequestParser {
    struct Bolt12OfferMetadata: Equatable, Sendable {
        let normalizedRequest: String
        let amountMsat: UInt64?
        let description: String?
    }

    private static let bolt12Alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let bolt12Values = Dictionary(
        uniqueKeysWithValues: bolt12Alphabet.enumerated().map { ($0.element, $0.offset) }
    )
    private static let knownOfferTypes: Set<UInt64> = [2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22]
    private static let maximumBitcoinAmountMsat: UInt64 = 2_100_000_000_000_000_000

    static func normalizeLightningRequest(_ request: String) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let lightningPrefixes = ["lightning://", "lightning:"]

        for prefix in lightningPrefixes where trimmedRequest.lowercased().hasPrefix(prefix) {
            return String(trimmedRequest.dropFirst(prefix.count))
        }

        return trimmedRequest
    }

    static func normalizeBitcoinRequest(_ request: String) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let bitcoinPrefixes = ["bitcoin://", "bitcoin:"]

        let withoutScheme: String
        if let prefix = bitcoinPrefixes.first(where: { trimmedRequest.lowercased().hasPrefix($0) }) {
            withoutScheme = String(trimmedRequest.dropFirst(prefix.count))
        } else {
            withoutScheme = trimmedRequest
        }

        return withoutScheme.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? withoutScheme
    }

    static func isBitcoinAddress(_ request: String) -> Bool {
        let normalizedRequest = normalizeBitcoinRequest(request)
        return BitcoinAddressValidator.isValidAddress(normalizedRequest)
    }

    static func isHumanReadableLightningAddress(_ request: String) -> Bool {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmedRequest.firstIndex(of: "@") else { return false }
        let user = trimmedRequest[trimmedRequest.startIndex..<atIndex]
        let domain = trimmedRequest[trimmedRequest.index(after: atIndex)...]
        return !user.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    static func paymentMethod(for request: String) -> PaymentMethodKind? {
        if isHumanReadableLightningAddress(request) {
            return nil
        }

        let normalizedRequest = PaymentRequestDecoder.encodedLightningRequest(from: request)
            ?? normalizeLightningRequest(request)
        if !normalizedRequest.isEmpty,
           let decodedRequest = try? decodeInvoice(invoiceStr: normalizedRequest) {
            switch decodedRequest.paymentType {
            case .bolt11:
                return .bolt11
            case .bolt12:
                return .bolt12
            }
        }

        if bolt12OfferMetadata(from: normalizedRequest) != nil {
            return .bolt12
        }

        if isBitcoinAddress(request) {
            return .onchain
        }

        return nil
    }

    /// Parses the BOLT12 text envelope and the small subset of offer TLVs the
    /// send flow needs. CDK currently rejects valid amountless offers with an
    /// empty description, even though BOLT12 permits them, so this standards-
    /// envelope/TLV fallback keeps recognition independent from that stricter
    /// decoder; CDK still performs the final protocol validation when quoting.
    static func bolt12OfferMetadata(from request: String) -> Bolt12OfferMetadata? {
        guard let normalized = normalizeBolt12Offer(request),
              normalized.hasPrefix("lno1") else {
            return nil
        }

        let encoded = normalized.dropFirst(4)
        guard !encoded.isEmpty else { return nil }
        let values = encoded.compactMap { bolt12Values[$0] }
        guard values.count == encoded.count,
              let bytes = convertBolt12Bits(values) else {
            return nil
        }

        var cursor = 0
        var previousType: UInt64?
        var amountMsat: UInt64?
        var sawAmount = false
        var sawDescription = false
        var sawCurrency = false
        var description: String?
        var hasPaths = false
        var hasIssuerID = false

        while cursor < bytes.count {
            guard let type = readBigSize(bytes, cursor: &cursor),
                  let length = readBigSize(bytes, cursor: &cursor),
                  length <= UInt64(bytes.count - cursor) else {
                return nil
            }
            if let previousType, type <= previousType { return nil }
            previousType = type

            guard (1...79).contains(type) || (1_000_000_000...1_999_999_999).contains(type) else {
                return nil
            }
            // Unknown odd records are optional extensions; unknown even
            // records are mandatory and make the offer unreadable.
            guard type % 2 != 0 || knownOfferTypes.contains(type) else { return nil }

            let fieldEnd = cursor + Int(length)
            let field = Array(bytes[cursor..<fieldEnd])
            cursor = fieldEnd

            switch type {
            case 2:
                guard !field.isEmpty, field.count.isMultiple(of: 32) else { return nil }
            case 6:
                guard field.count == 3, field.allSatisfy({ (65...90).contains($0) }) else { return nil }
                sawCurrency = true
            case 8:
                guard let value = decodeTruncatedUInt64(field),
                      value > 0,
                      value <= maximumBitcoinAmountMsat else {
                    return nil
                }
                sawAmount = true
                amountMsat = value
            case 10:
                guard let value = String(bytes: field, encoding: .utf8) else { return nil }
                sawDescription = true
                description = value.isEmpty ? nil : value
            case 14, 20:
                guard decodeTruncatedUInt64(field) != nil else { return nil }
            case 16:
                hasPaths = !field.isEmpty
            case 18:
                guard String(bytes: field, encoding: .utf8) != nil else { return nil }
            case 22:
                guard field.count == 33,
                      (field.first == 0x02 || field.first == 0x03) else {
                    return nil
                }
                hasIssuerID = true
            default:
                break
            }
        }

        guard hasPaths || hasIssuerID,
              !sawAmount || sawDescription,
              !sawCurrency || sawAmount else {
            return nil
        }

        // A currency-denominated offer's amount is not millisatoshis. Leave
        // those to CDK rather than misrouting them as an amountless offer.
        guard !sawCurrency else { return nil }

        return Bolt12OfferMetadata(
            normalizedRequest: normalized,
            amountMsat: amountMsat,
            description: description
        )
    }

    /// BOLT12 uses bech32-style data without a checksum. It also explicitly
    /// permits `+` followed by optional whitespace as a continuation marker.
    private static func normalizeBolt12Offer(_ request: String) -> String? {
        let raw = normalizeLightningRequest(request)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        var compact = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            if character == "+" {
                guard let previous = compact.last, isBolt12Character(previous) else { return nil }
                index = raw.index(after: index)
                while index < raw.endIndex, raw[index].isWhitespace {
                    index = raw.index(after: index)
                }
                guard index < raw.endIndex,
                      isBolt12Character(raw[index]) else {
                    return nil
                }
                continue
            }
            guard !character.isWhitespace else { return nil }
            compact.append(character)
            index = raw.index(after: index)
        }

        let hasLowercase = compact.contains { $0.isLowercase }
        let hasUppercase = compact.contains { $0.isUppercase }
        guard !(hasLowercase && hasUppercase) else { return nil }
        return compact.lowercased()
    }

    private static func isBolt12Character(_ character: Character) -> Bool {
        let lowercased = Character(String(character).lowercased())
        return bolt12Values[lowercased] != nil
    }

    private static func convertBolt12Bits(_ values: [Int]) -> [UInt8]? {
        var accumulator = 0
        var bitCount = 0
        var bytes: [UInt8] = []

        for value in values {
            guard (0..<32).contains(value) else { return nil }
            accumulator = ((accumulator << 5) | value) & 0x0fff
            bitCount += 5
            while bitCount >= 8 {
                bitCount -= 8
                bytes.append(UInt8((accumulator >> bitCount) & 0xff))
            }
        }

        // At most four zero bits may remain after conversion.
        guard bitCount < 5,
              ((accumulator << (8 - bitCount)) & 0xff) == 0 else {
            return nil
        }
        return bytes
    }

    private static func readBigSize(_ bytes: [UInt8], cursor: inout Int) -> UInt64? {
        guard cursor < bytes.count else { return nil }
        let marker = bytes[cursor]
        cursor += 1

        let byteCount: Int
        let minimum: UInt64
        switch marker {
        case 0x00...0xfc:
            return UInt64(marker)
        case 0xfd:
            byteCount = 2
            minimum = 0xfd
        case 0xfe:
            byteCount = 4
            minimum = 0x1_0000
        case 0xff:
            byteCount = 8
            minimum = 0x1_0000_0000
        default:
            return nil
        }

        guard cursor + byteCount <= bytes.count else { return nil }
        var value: UInt64 = 0
        for byte in bytes[cursor..<cursor + byteCount] {
            value = (value << 8) | UInt64(byte)
        }
        cursor += byteCount
        return value >= minimum ? value : nil
    }

    private static func decodeTruncatedUInt64(_ bytes: [UInt8]) -> UInt64? {
        guard bytes.count <= 8,
              bytes.isEmpty || bytes.first != 0 else {
            return nil
        }
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

private enum BitcoinAddressValidator {
    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let bech32Alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let bech32Generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    private static let base58VersionBytes: Set<UInt8> = [0x00, 0x05, 0x6f, 0xc4]
    private static let bech32Hrp: Set<String> = ["bc", "tb", "bcrt"]

    private static var base58Values: [Character: Int] {
        Dictionary(uniqueKeysWithValues: base58Alphabet.enumerated().map { ($0.element, $0.offset) })
    }

    private static var bech32Values: [Character: Int] {
        Dictionary(uniqueKeysWithValues: bech32Alphabet.enumerated().map { ($0.element, $0.offset) })
    }

    static func isValidAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return false
        }

        if trimmed.contains("@") {
            return false
        }

        return isValidBech32Address(trimmed) || isValidBase58CheckAddress(trimmed)
    }

    private static func isValidBase58CheckAddress(_ address: String) -> Bool {
        guard let decoded = decodeBase58(address), decoded.count == 25 else {
            return false
        }

        let payload = decoded.prefix(21)
        let checksum = decoded.suffix(4)
        guard let version = payload.first, base58VersionBytes.contains(version) else {
            return false
        }

        let firstHash = SHA256.hash(data: Data(payload))
        let secondHash = SHA256.hash(data: Data(firstHash))
        return Array(secondHash.prefix(4)) == Array(checksum)
    }

    private static func decodeBase58(_ address: String) -> [UInt8]? {
        var bytes: [UInt8] = []

        for character in address {
            guard let value = base58Values[character] else {
                return nil
            }

            var carry = value
            for index in bytes.indices.reversed() {
                let total = Int(bytes[index]) * 58 + carry
                bytes[index] = UInt8(total & 0xff)
                carry = total >> 8
            }

            while carry > 0 {
                bytes.insert(UInt8(carry & 0xff), at: 0)
                carry >>= 8
            }
        }

        let leadingZeroes = address.prefix { $0 == "1" }.count
        return Array(repeating: UInt8(0), count: leadingZeroes) + bytes
    }

    private static func isValidBech32Address(_ address: String) -> Bool {
        let scalars = address.unicodeScalars
        guard scalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else {
            return false
        }

        let hasLowercase = scalars.contains { CharacterSet.lowercaseLetters.contains($0) }
        let hasUppercase = scalars.contains { CharacterSet.uppercaseLetters.contains($0) }
        guard !(hasLowercase && hasUppercase) else {
            return false
        }

        let lowercasedAddress = address.lowercased()
        guard let separatorIndex = lowercasedAddress.lastIndex(of: "1") else {
            return false
        }

        let hrp = String(lowercasedAddress[..<separatorIndex])
        let dataStart = lowercasedAddress.index(after: separatorIndex)
        let dataPart = lowercasedAddress[dataStart...]

        guard bech32Hrp.contains(hrp), dataPart.count >= 7 else {
            return false
        }

        let dataValues = dataPart.compactMap { bech32Values[$0] }
        guard dataValues.count == dataPart.count else {
            return false
        }

        let checksum = bech32Polymod(hrpExpand(hrp) + dataValues)
        let encodingIsBech32 = checksum == 1
        let encodingIsBech32m = checksum == 0x2bc830a3
        guard encodingIsBech32 || encodingIsBech32m else {
            return false
        }

        let witnessData = Array(dataValues.dropLast(6))
        guard let version = witnessData.first, version <= 16 else {
            return false
        }

        guard let program = convertBits(Array(witnessData.dropFirst()), fromBits: 5, toBits: 8, pad: false),
              (2...40).contains(program.count) else {
            return false
        }

        if version == 0 {
            return encodingIsBech32 && (program.count == 20 || program.count == 32)
        }

        return encodingIsBech32m
    }

    private static func hrpExpand(_ hrp: String) -> [Int] {
        let scalars = hrp.unicodeScalars.map { Int($0.value) }
        return scalars.map { $0 >> 5 } + [0] + scalars.map { $0 & 31 }
    }

    private static func bech32Polymod(_ values: [Int]) -> Int {
        var checksum = 1

        for value in values {
            let top = checksum >> 25
            checksum = ((checksum & 0x1ffffff) << 5) ^ value

            for index in 0..<5 where ((top >> index) & 1) == 1 {
                checksum ^= bech32Generator[index]
            }
        }

        return checksum
    }

    private static func convertBits(_ data: [Int], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var accumulator = 0
        var bits = 0
        var result: [UInt8] = []
        let maxValue = (1 << toBits) - 1
        let maxAccumulator = (1 << (fromBits + toBits - 1)) - 1

        for value in data {
            guard value >= 0 && (value >> fromBits) == 0 else {
                return nil
            }

            accumulator = ((accumulator << fromBits) | value) & maxAccumulator
            bits += fromBits

            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((accumulator >> bits) & maxValue))
            }
        }

        if pad {
            if bits > 0 {
                result.append(UInt8((accumulator << (toBits - bits)) & maxValue))
            }
        } else if bits >= fromBits || ((accumulator << (toBits - bits)) & maxValue) != 0 {
            return nil
        }

        return result
    }
}
