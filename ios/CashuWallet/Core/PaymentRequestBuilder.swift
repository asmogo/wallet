import Foundation

enum PaymentRequestBuilder {
    /// In-band NUT-18 request: omit transports so the payer writes the token
    /// back to the emulated tag instead of delivering it over Nostr.
    static func buildNFC(request: CashuRequest) -> String {
        var fields: [(Nut18Key, Nut18Value)] = [(.text("i"), .text(request.id))]
        if let amount = request.amount, amount > 0 { fields.append((.text("a"), .uint(amount))) }
        fields.append((.text("u"), .text(request.unit)))
        fields.append((.text("s"), .bool(!request.reusable)))
        if !request.mints.isEmpty {
            fields.append((.text("m"), .array(request.mints.map { .text($0) })))
        }
        if let memo = request.memo, !memo.isEmpty { fields.append((.text("d"), .text(memo))) }
        return "creqA" + Base64URL.encode(Nut18CBOR.encode(.map(fields)))
    }

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
        nip: String = "17",
        p2pkPubkeyHex: String? = nil
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
        // Optional NUT-10 lock (NUT-18). A payer's wallet reads this and locks the
        // proofs it creates to the given P2PK pubkey, so only its holder can
        // redeem them. Encoded as cashu-ts does: `"nut10": {"k": kind, "d": data}`.
        if let p2pkPubkeyHex, !p2pkPubkeyHex.isEmpty {
            let nut10: [(Nut18Key, Nut18Value)] = [
                (.text("k"), .text("P2PK")),
                (.text("d"), .text(p2pkPubkeyHex)),
            ]
            request.append((.text("nut10"), .map(nut10)))
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

enum CashuRequestNostrReadiness: Equatable {
    struct RequestConfiguration: Equatable {
        let publicKeyHex: String
        let relays: [String]
    }

    struct DeliveryNotice: Equatable {
        let title: String
        let message: String
    }

    case ready(configuration: RequestConfiguration)
    case blocked(recoveryMessage: String, requestConfiguration: RequestConfiguration?)

    static let nostrKeyRecovery =
        "Your Nostr key isn't ready. Check Settings → Nostr → Nostr key, then try again."
    static let relayRecovery =
        "No usable Nostr relay is configured. Add a ws:// or wss:// relay in Settings → Nostr → Relays, then try again."
    static let listenerRecovery =
        "Cashu Request listening is off. Turn on Settings → Privacy → Listen for payment requests, then try again."

    var recoveryMessage: String? {
        guard case .blocked(let recoveryMessage, _) = self else { return nil }
        return recoveryMessage
    }

    /// The key and relay data needed to encode a request. A listener-disabled
    /// wallet still has a valid configuration, so request creation can continue
    /// while the detail screen explains that receiving is currently unavailable.
    var requestConfiguration: RequestConfiguration? {
        switch self {
        case .ready(let configuration):
            return configuration
        case .blocked(_, let requestConfiguration):
            return requestConfiguration
        }
    }

    /// Contextual copy for an already-created request. This deliberately avoids
    /// the "try again" language used by creation errors because the QR is valid
    /// and remains shareable while the wallet's receive path is unavailable.
    var deliveryNotice: DeliveryNotice? {
        guard let recoveryMessage else { return nil }
        switch recoveryMessage {
        case Self.nostrKeyRecovery:
            return DeliveryNotice(
                title: "Nostr key unavailable",
                message: "This wallet can't receive payments for this request. Check Settings → Nostr → Nostr key."
            )
        case Self.relayRecovery:
            return DeliveryNotice(
                title: "No usable relay",
                message: "This wallet can't receive payments for this request. Add a ws:// or wss:// relay in Settings → Nostr → Relays."
            )
        default:
            return DeliveryNotice(
                title: "Payment requests are off",
                message: "You can share this request, but this wallet won't receive payments until you turn on Settings → Privacy → Listen for payment requests."
            )
        }
    }

    @MainActor
    static func current() -> CashuRequestNostrReadiness {
        let nostr = NostrService.shared
        let settings = SettingsManager.shared
        return evaluate(
            isIdentityInitialized: nostr.isInitialized,
            publicKeyHex: nostr.publicKeyHex,
            privateKeyHex: nostr.getPrivateKeyHex(),
            relays: settings.nostrRelays,
            listenerEnabled: settings.enablePaymentRequests
        )
    }

    static func evaluate(
        isIdentityInitialized: Bool,
        publicKeyHex: String,
        privateKeyHex: String?,
        relays: [String],
        listenerEnabled: Bool
    ) -> CashuRequestNostrReadiness {
        guard isIdentityInitialized,
              isHexKey(publicKeyHex),
              privateKeyHex.map(isHexKey) == true else {
            return .blocked(
                recoveryMessage: nostrKeyRecovery,
                requestConfiguration: nil
            )
        }
        let usableRelays = normalizedRelays(relays)
        guard !usableRelays.isEmpty else {
            return .blocked(
                recoveryMessage: relayRecovery,
                requestConfiguration: nil
            )
        }
        let configuration = RequestConfiguration(
            publicKeyHex: publicKeyHex,
            relays: usableRelays
        )
        guard listenerEnabled else {
            return .blocked(
                recoveryMessage: listenerRecovery,
                requestConfiguration: configuration
            )
        }
        return .ready(configuration: configuration)
    }

    static func normalizedRelays(_ relays: [String]) -> [String] {
        var seen: Set<String> = []
        return relays.compactMap { relay -> String? in
            let trimmed = relay.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let components = URLComponents(string: trimmed),
                  let scheme = components.scheme?.lowercased(),
                  ["ws", "wss"].contains(scheme),
                  components.host?.isEmpty == false,
                  seen.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }
    }

    private static func isHexKey(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }
    }
}

// MARK: - Locked Receive Request

/// Builds the "receive locked ecash" artifact: a NUT-18 Cashu payment request that
/// locks any payment to the wallet's primary (seed-derived) P2PK key and routes the
/// proofs back over Nostr. Anyone who pays it sends ecash that only this wallet can
/// redeem. Shared by the Receive menu and the Locked Ecash settings hub.
enum LockedReceiveRequest {
    @MainActor
    static func build(amount: UInt64? = nil) -> String? {
        guard case let .ready(configuration) = CashuRequestNostrReadiness.current(),
              let pubkey = SettingsManager.shared.primaryP2PKPublicKey else { return nil }
        return try? PaymentRequestBuilder.build(
            id: CashuRequest.newId(),
            amount: amount,
            unit: "sat",
            mints: [],
            description: nil,
            nostrPubkeyHex: configuration.publicKeyHex,
            relays: configuration.relays,
            p2pkPubkeyHex: pubkey
        )
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
