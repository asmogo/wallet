import Foundation
import CryptoKit
import P256K
import Security
#if canImport(CommonCrypto)
import CommonCrypto
#endif

struct DiscoveredNostrMintBackup: Identifiable, Codable, Hashable {
    let url: String
    let timestamp: Date
    var selected: Bool

    var id: String { url }
}

extension NostrIncomingEvent: Sendable {}

@MainActor
final class NostrMintBackupService: ObservableObject {
    static let shared = NostrMintBackupService()

    @Published private(set) var isBackingUp = false
    @Published private(set) var isSearching = false
    @Published private(set) var lastBackupDate: Date?
    @Published var discoveredMints: [DiscoveredNostrMintBackup] = []
    @Published var lastError: String?

    private let keychainService = KeychainService()

    private init() {
        if let storedDate = UserDefaults.standard.object(forKey: StorageKeys.nostrMintBackupLastBackupDate) as? Date {
            lastBackupDate = storedDate
        }
    }

    func backupCurrentMintsIfEnabled(mintURLs: [String]) async {
        guard SettingsManager.shared.nostrMintBackupEnabled else { return }
        guard !mintURLs.isEmpty else { return }

        do {
            try await backupMintURLs(mintURLs)
        } catch {
            lastError = error.localizedDescription
            AppLogger.wallet.error("Nostr mint backup failed: \(error)")
        }
    }

    func backupMintURLs(_ mintURLs: [String]) async throws {
        guard SettingsManager.shared.useWebsockets else {
            throw NostrMintBackupError.webSocketsDisabled
        }
        guard let mnemonic = try keychainService.loadMnemonic(), !mnemonic.isEmpty else {
            throw NostrMintBackupError.missingMnemonic
        }

        let uniqueMints = Self.normalizedMintURLs(mintURLs)
        guard !uniqueMints.isEmpty else {
            throw NostrMintBackupError.noMints
        }

        let relays = SettingsManager.shared.nostrRelays
        guard !NostrMintBackupRelayClient.normalizeRelays(relays).isEmpty else {
            throw NostrMintBackupError.noRelays
        }

        isBackingUp = true
        defer { isBackingUp = false }

        let keys = try Self.backupKeypair(for: mnemonic)
        let payload = MintBackupPayload(mints: uniqueMints, timestamp: Int(Date().timeIntervalSince1970))
        let payloadData = try JSONEncoder().encode(payload)
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw NostrMintBackupError.invalidUTF8
        }

        let encrypted = try NIP44.encrypt(
            plaintext: payloadString,
            senderPrivateKey: keys.privateKey,
            recipientPubkeyHex: keys.publicKeyHex
        )
        let event = try Self.signEvent(
            privateKey: keys.privateKey,
            kind: 30078,
            tags: [["d", "mint-list"], ["client", "cashu.me"]],
            content: encrypted
        )

        try await NostrMintBackupRelayClient.publish(event: event, to: relays)
        let date = Date()
        lastBackupDate = date
        lastError = nil
        UserDefaults.standard.set(date, forKey: StorageKeys.nostrMintBackupLastBackupDate)
    }

    func searchBackups(using mnemonic: String) async throws -> [DiscoveredNostrMintBackup] {
        guard SettingsManager.shared.useWebsockets else {
            throw NostrMintBackupError.webSocketsDisabled
        }

        let cleanedMnemonic = mnemonic
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !cleanedMnemonic.isEmpty else {
            throw NostrMintBackupError.missingMnemonic
        }

        let relays = SettingsManager.shared.nostrRelays
        guard !NostrMintBackupRelayClient.normalizeRelays(relays).isEmpty else {
            throw NostrMintBackupError.noRelays
        }

        isSearching = true
        defer { isSearching = false }

        let keys = try Self.backupKeypair(for: cleanedMnemonic)
        let events = await NostrMintBackupRelayClient.fetchEvents(
            from: relays,
            filter: NostrMintBackupFilter(
                kinds: [30078],
                authors: [keys.publicKeyHex],
                since: nil,
                limit: 10,
                tags: ["d": ["mint-list"]]
            )
        )

        var latestTimestampByMint: [String: Date] = [:]
        for event in events {
            guard Self.verifyEvent(event) else { continue }

            do {
                let decrypted = try NIP44.decrypt(
                    payload: event.content,
                    recipientPrivateKey: keys.privateKey,
                    senderPubkeyHex: keys.publicKeyHex
                )
                guard let data = decrypted.data(using: .utf8) else { continue }
                let payload = try JSONDecoder().decode(MintBackupPayload.self, from: data)
                let date = Date(timeIntervalSince1970: TimeInterval(payload.timestamp))

                for mint in payload.mints {
                    let trimmed = mint.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    if latestTimestampByMint[trimmed].map({ $0 < date }) ?? true {
                        latestTimestampByMint[trimmed] = date
                    }
                }
            } catch {
                continue
            }
        }

        let sorted = latestTimestampByMint
            .map { DiscoveredNostrMintBackup(url: $0.key, timestamp: $0.value, selected: true) }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.url < rhs.url
                }
                return lhs.timestamp > rhs.timestamp
            }

        discoveredMints = sorted
        lastError = nil
        return sorted
    }

    func setSelected(_ selected: Bool, for mintURL: String) {
        guard let index = discoveredMints.firstIndex(where: { $0.url == mintURL }) else { return }
        discoveredMints[index].selected = selected
    }

    func selectAllDiscovered() {
        discoveredMints = discoveredMints.map { item in
            var copy = item
            copy.selected = true
            return copy
        }
    }

    func clearDiscovered() {
        discoveredMints = []
        lastError = nil
    }

    func resetForWalletBoundary() {
        clearDiscovered()
        lastBackupDate = nil
        UserDefaults.standard.removeObject(forKey: StorageKeys.nostrMintBackupLastBackupDate)
    }

    private struct MintBackupPayload: Codable {
        let mints: [String]
        let timestamp: Int
    }

    static func backupKeypair(for mnemonic: String) throws -> (privateKey: Data, privateKeyHex: String, publicKeyHex: String) {
        let seed = try bip39Seed(from: mnemonic)
        var material = Data(seed)
        material.append(Data("cashu-mint-backup".utf8))
        let privateKey = Data(SHA256.hash(data: material))
        let schnorrKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKey)
        let publicKeyHex = hexString(schnorrKey.xonly.bytes)
        return (privateKey, hexString(privateKey), publicKeyHex)
    }

    private static func normalizedMintURLs(_ mintURLs: [String]) -> [String] {
        Array(
            Set(
                mintURLs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    private static func bip39Seed(from mnemonic: String, passphrase: String = "") throws -> Data {
        #if canImport(CommonCrypto)
        let normalizedMnemonic = mnemonic.decomposedStringWithCompatibilityMapping
        let normalizedSalt = ("mnemonic" + passphrase).decomposedStringWithCompatibilityMapping

        guard let passwordData = normalizedMnemonic.data(using: .utf8),
              let saltData = normalizedSalt.data(using: .utf8) else {
            throw NostrMintBackupError.keyDerivationFailed
        }

        var derived = Data(repeating: 0, count: 64)
        let derivedCount = derived.count
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                saltData.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        2048,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedCount
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw NostrMintBackupError.keyDerivationFailed
        }

        return derived
        #else
        throw NostrMintBackupError.commonCryptoUnavailable
        #endif
    }

    private static func signEvent(
        privateKey privateKeyData: Data,
        kind: Int,
        tags: [[String]],
        content: String,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrIncomingEvent {
        let privateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKeyData)
        let pubkeyHex = hexString(privateKey.xonly.bytes)
        let eventId = try calculateEventId(
            pubkey: pubkeyHex,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )

        guard let eventIdData = Data(hexString: eventId), eventIdData.count == 32 else {
            throw NostrMintBackupError.signingFailed
        }

        var messageBytes = Array(eventIdData)
        var auxRand = try secureRandomBytes(count: 32)
        let signature = try privateKey.signature(message: &messageBytes, auxiliaryRand: &auxRand)

        return NostrIncomingEvent(
            id: eventId,
            pubkey: pubkeyHex,
            createdAt: Int64(createdAt),
            kind: kind,
            tags: tags,
            content: content,
            sig: hexString(signature.dataRepresentation)
        )
    }

    private static func verifyEvent(_ event: NostrIncomingEvent) -> Bool {
        guard let eventIdData = Data(hexString: event.id),
              let signatureData = Data(hexString: event.sig),
              let pubkeyData = Data(hexString: event.pubkey),
              eventIdData.count == 32,
              signatureData.count == 64,
              pubkeyData.count == 32 else {
            return false
        }

        do {
            let expectedEventId = try calculateEventId(
                pubkey: event.pubkey,
                createdAt: Int(event.createdAt),
                kind: event.kind,
                tags: event.tags,
                content: event.content
            )
            guard expectedEventId == event.id else {
                return false
            }

            let xonlyKey = P256K.Schnorr.XonlyKey(dataRepresentation: pubkeyData, keyParity: 0)
            let signature = try P256K.Schnorr.SchnorrSignature(dataRepresentation: signatureData)
            var messageBytes = Array(eventIdData)
            return xonlyKey.isValid(signature, for: &messageBytes)
        } catch {
            return false
        }
    }

    private static func calculateEventId(
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String
    ) throws -> String {
        let commitment = NostrCommitment(
            zero: 0,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(commitment)
        return hexString(SHA256.hash(data: data))
    }

    private static func secureRandomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw NostrMintBackupError.randomGenerationFailed
        }
        return bytes
    }

    private static func hexString<T: Sequence>(_ bytes: T) -> String where T.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

struct NostrMintBackupFilter: Sendable {
    var kinds: [Int]?
    var authors: [String]?
    var since: Int?
    var limit: Int?
    var tags: [String: [String]] = [:]

    func asJSONObject() -> [String: Any] {
        var object: [String: Any] = [:]
        if let kinds {
            object["kinds"] = kinds
        }
        if let authors {
            object["authors"] = authors
        }
        if let since {
            object["since"] = since
        }
        if let limit {
            object["limit"] = limit
        }
        for (tag, values) in tags where !values.isEmpty {
            object["#\(tag)"] = values
        }
        return object
    }
}

enum NostrMintBackupRelayClient {
    static func publish(event: NostrIncomingEvent, to relays: [String]) async throws {
        let normalizedRelays = normalizeRelays(relays)
        guard !normalizedRelays.isEmpty else {
            throw NostrMintBackupError.noRelays
        }

        let eventData = try JSONEncoder().encode(event)
        let eventObject = try JSONSerialization.jsonObject(with: eventData)
        let messageData = try JSONSerialization.data(
            withJSONObject: ["EVENT", eventObject],
            options: [.withoutEscapingSlashes]
        )
        let messageString = String(decoding: messageData, as: UTF8.self)

        let successCount = await withTaskGroup(of: Bool.self) { group in
            for relay in normalizedRelays {
                group.addTask {
                    do {
                        try await publishToRelay(relay: relay, message: messageString)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var successes = 0
            for await success in group where success {
                successes += 1
            }
            return successes
        }

        guard successCount > 0 else {
            throw NostrMintBackupError.noRelayAcknowledged
        }
    }

    static func fetchEvents(
        from relays: [String],
        filter: NostrMintBackupFilter,
        timeout: TimeInterval = 4
    ) async -> [NostrIncomingEvent] {
        let normalizedRelays = normalizeRelays(relays)
        let results = await withTaskGroup(of: [NostrIncomingEvent].self) { group in
            for relay in normalizedRelays {
                group.addTask {
                    await fetchFromRelay(relay: relay, filter: filter, timeout: timeout)
                }
            }

            var merged: [NostrIncomingEvent] = []
            for await events in group {
                merged.append(contentsOf: events)
            }
            return merged
        }

        var seenIds = Set<String>()
        return results.filter { event in
            seenIds.insert(event.id).inserted
        }
    }

    static func normalizeRelays(_ relays: [String]) -> [String] {
        var seen = Set<String>()
        return relays.compactMap { relay in
            let normalized = relay.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = normalized.lowercased()
            guard lower.hasPrefix("wss://") || lower.hasPrefix("ws://") else { return nil }
            guard seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private static func publishToRelay(relay: String, message: String) async throws {
        let (session, task) = try makeConnection(relay: relay)
        defer {
            task.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        task.resume()
        try await task.send(.string(message))
    }

    private static func fetchFromRelay(
        relay: String,
        filter: NostrMintBackupFilter,
        timeout: TimeInterval
    ) async -> [NostrIncomingEvent] {
        do {
            let (session, task) = try makeConnection(relay: relay)
            defer {
                task.cancel(with: .normalClosure, reason: nil)
                session.invalidateAndCancel()
            }

            let subscriptionId = UUID().uuidString
            let requestData = try JSONSerialization.data(
                withJSONObject: ["REQ", subscriptionId, filter.asJSONObject()],
                options: [.withoutEscapingSlashes]
            )
            let requestString = String(decoding: requestData, as: UTF8.self)

            task.resume()
            try await task.send(.string(requestString))

            var events: [NostrIncomingEvent] = []
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                guard let message = try await receiveMessage(task: task, timeout: 0.75) else {
                    break
                }

                switch parseRelayMessage(message) {
                case .event(let event):
                    events.append(event)
                case .eose:
                    return events
                case .other:
                    continue
                }
            }
            return events
        } catch {
            return []
        }
    }

    private static func makeConnection(relay: String) throws -> (URLSession, URLSessionWebSocketTask) {
        guard let url = URL(string: relay) else {
            throw URLError(.badURL)
        }
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: url)
        return (session, task)
    }

    private static func receiveMessage(
        task: URLSessionWebSocketTask,
        timeout: TimeInterval
    ) async throws -> URLSessionWebSocketTask.Message? {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message?.self) { group in
            group.addTask {
                try await task.receive()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private enum ParsedRelayMessage {
        case event(NostrIncomingEvent)
        case eose
        case other
    }

    private static func parseRelayMessage(_ message: URLSessionWebSocketTask.Message) -> ParsedRelayMessage {
        let text: String
        switch message {
        case .string(let string):
            text = string
        case .data(let data):
            text = String(decoding: data, as: UTF8.self)
        @unknown default:
            return .other
        }

        guard let data = text.data(using: .utf8),
              let rawArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = rawArray.first as? String else {
            return .other
        }

        if type == "EOSE" {
            return .eose
        }

        guard type == "EVENT",
              rawArray.count >= 3,
              JSONSerialization.isValidJSONObject(rawArray[2]),
              let eventData = try? JSONSerialization.data(withJSONObject: rawArray[2]),
              let event = try? JSONDecoder().decode(NostrIncomingEvent.self, from: eventData) else {
            return .other
        }

        return .event(event)
    }
}

enum NostrMintBackupError: LocalizedError {
    case missingMnemonic
    case noMints
    case noRelays
    case noRelayAcknowledged
    case invalidUTF8
    case signingFailed
    case keyDerivationFailed
    case commonCryptoUnavailable
    case randomGenerationFailed
    case webSocketsDisabled

    var errorDescription: String? {
        switch self {
        case .missingMnemonic:
            return "Wallet seed is unavailable."
        case .noMints:
            return "No mint URLs to back up."
        case .noRelays:
            return "No Nostr relays are configured."
        case .noRelayAcknowledged:
            return "No relay accepted the mint backup."
        case .invalidUTF8:
            return "Mint backup payload is not valid UTF-8."
        case .signingFailed:
            return "Couldn't sign the mint backup."
        case .keyDerivationFailed:
            return "Couldn't derive the Nostr mint backup key."
        case .commonCryptoUnavailable:
            return "Required cryptography support is unavailable."
        case .randomGenerationFailed:
            return "Couldn't generate secure randomness."
        case .webSocketsDisabled:
            return "Websocket connections are disabled."
        }
    }
}
