import Foundation
import CryptoKit

struct DiscoveredNostrMintBackup: Identifiable, Codable, Hashable {
    let url: String
    let timestamp: Date
    var selected: Bool

    var id: String { url }
}

@MainActor
final class NostrMintBackupService: ObservableObject {
    static let shared = NostrMintBackupService()

    @Published private(set) var isBackingUp = false
    @Published private(set) var isSearching = false
    @Published private(set) var lastBackupDate: Date?
    @Published var discoveredMints: [DiscoveredNostrMintBackup] = []
    @Published var lastError: String?

    private let keychainService = KeychainService()
    private let lastBackupDateKey = "nostrMintBackup.lastBackupDate"

    private init() {
        if let storedDate = UserDefaults.standard.object(forKey: lastBackupDateKey) as? Date {
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
        }
    }

    func backupMintURLs(_ mintURLs: [String]) async throws {
        guard let mnemonic = try keychainService.loadMnemonic(), !mnemonic.isEmpty else {
            return
        }
        let keys = try Self.backupKeypair(for: mnemonic)
        let uniqueMints = Array(Set(mintURLs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).sorted()
        guard !uniqueMints.isEmpty else { return }

        let payload = MintBackupPayload(mints: uniqueMints, timestamp: Int(Date().timeIntervalSince1970))
        let payloadData = try JSONEncoder().encode(payload)
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw NostrSupportError.invalidUTF8
        }

        isBackingUp = true
        defer { isBackingUp = false }

        let encrypted = try NostrCrypto.nip44Encrypt(plaintext: payloadString, privateKeyHex: keys.privateKeyHex, publicKeyHex: keys.publicKeyHex)
        let event = try NostrCrypto.signEvent(
            privateKeyHex: keys.privateKeyHex,
            kind: 30078,
            tags: [["d", "mint-list"], ["client", "cashu.me"]],
            content: encrypted
        )
        try await NostrRelayClient.publish(event: event, to: SettingsManager.shared.nostrRelays)
        lastBackupDate = Date()
        UserDefaults.standard.set(lastBackupDate, forKey: lastBackupDateKey)
    }

    func searchBackups(using mnemonic: String) async throws -> [DiscoveredNostrMintBackup] {
        isSearching = true
        defer { isSearching = false }

        let keys = try Self.backupKeypair(for: mnemonic)
        let events = await NostrRelayClient.fetchEvents(
            from: SettingsManager.shared.nostrRelays,
            filter: NostrFilter(
                kinds: [30078],
                authors: [keys.publicKeyHex],
                since: nil,
                limit: 10,
                tags: ["d": ["mint-list"]]
            )
        )

        var latestTimestampByMint: [String: Date] = [:]
        for event in events {
            guard NostrCrypto.verifyEvent(event) else { continue }
            do {
                let decrypted = try NostrCrypto.nip44Decrypt(payload: event.content, privateKeyHex: keys.privateKeyHex, publicKeyHex: keys.publicKeyHex)
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

    private struct MintBackupPayload: Codable {
        let mints: [String]
        let timestamp: Int
    }

    static func backupKeypair(for mnemonic: String) throws -> (privateKeyHex: String, publicKeyHex: String) {
        let seed = try NostrCrypto.bip39Seed(from: mnemonic)
        var material = Data(seed)
        material.append(Data("cashu-mint-backup".utf8))
        let privateKeyHex = Data(SHA256.hash(data: material)).map { String(format: "%02x", $0) }.joined()
        let publicKeyHex = try NostrCrypto.publicKeyHex(for: privateKeyHex)
        return (privateKeyHex, publicKeyHex)
    }
}
