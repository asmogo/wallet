import Foundation

struct NostrIncomingEvent: Codable, Hashable, Sendable {
    let id: String
    let pubkey: String
    let createdAt: Int64
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String

    enum CodingKeys: String, CodingKey {
        case id
        case pubkey
        case createdAt = "created_at"
        case kind
        case tags
        case content
        case sig
    }
}

struct NostrRumor: Hashable {
    let id: String
    let pubkey: String
    let createdAt: Int64
    let kind: Int
    let tags: [[String]]
    let content: String
}

enum NIP17 {
    enum Error: Swift.Error {
        case decryptFailed
        case invalidSeal
        case invalidRumor
        case canonicalizeFailed
    }

    /// Unwrap an incoming kind:1059 gift wrap addressed to us. Returns the inner kind:14 rumor.
    static func unwrap(giftWrap event: NostrIncomingEvent, recipientPrivateKey: Data) throws -> NostrRumor {
        // Layer 1: decrypt wrap content with our private key + wrap.pubkey (ephemeral)
        let sealJSON: String
        do {
            sealJSON = try NIP44.decrypt(
                payload: event.content,
                recipientPrivateKey: recipientPrivateKey,
                senderPubkeyHex: event.pubkey
            )
        } catch {
            throw Error.decryptFailed
        }
        guard let seal = decodeEvent(sealJSON) else { throw Error.invalidSeal }
        guard seal.kind == 13 else { throw Error.invalidSeal }

        // Layer 2: decrypt seal content with our private key + seal.pubkey (real sender)
        let rumorJSON: String
        do {
            rumorJSON = try NIP44.decrypt(
                payload: seal.content,
                recipientPrivateKey: recipientPrivateKey,
                senderPubkeyHex: seal.pubkey
            )
        } catch {
            throw Error.decryptFailed
        }
        guard let rumor = decodeRumor(rumorJSON, expectedAuthor: seal.pubkey) else {
            throw Error.invalidRumor
        }
        return rumor
    }

    // MARK: - JSON helpers

    private static func decodeEvent(_ jsonString: String) -> NostrIncomingEvent? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NostrIncomingEvent.self, from: data)
    }

    private static func decodeRumor(_ jsonString: String, expectedAuthor: String) -> NostrRumor? {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let pubkey = (obj["pubkey"] as? String) ?? expectedAuthor
        guard pubkey == expectedAuthor else { return nil }
        let id = (obj["id"] as? String) ?? ""
        let createdAt = (obj["created_at"] as? NSNumber)?.int64Value
            ?? (obj["created_at"] as? Int64)
            ?? Int64((obj["created_at"] as? Int) ?? 0)
        let kind = (obj["kind"] as? Int) ?? 0
        let tags = (obj["tags"] as? [[String]]) ?? []
        let content = (obj["content"] as? String) ?? ""
        return NostrRumor(id: id, pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
    }
}
