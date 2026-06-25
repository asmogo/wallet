import Foundation
import Cdk

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

    var walletRepository: WalletRepository?

    private init() {
        if let storedDate = UserDefaults.standard.object(forKey: StorageKeys.nostrMintBackupLastBackupDate) as? Date {
            lastBackupDate = storedDate
        }
    }

    func backupCurrentMintsIfEnabled() async {
        guard SettingsManager.shared.nostrMintBackupEnabled else { return }
        do {
            try await backupMints()
        } catch {
            lastError = error.localizedDescription
            AppLogger.wallet.error("Nostr mint backup failed: \(error)")
        }
    }

    func backupMints() async throws {
        guard SettingsManager.shared.useWebsockets else {
            throw NostrMintBackupError.webSocketsDisabled
        }
        guard let walletRepository else {
            throw NostrMintBackupError.notInitialized
        }
        let relays = normalizedRelays(SettingsManager.shared.nostrRelays)
        guard !relays.isEmpty else {
            throw NostrMintBackupError.noRelays
        }

        isBackingUp = true
        defer { isBackingUp = false }

        _ = try await walletRepository.backupMints(
            relays: relays,
            options: BackupOptions(client: "cashu.me")
        )

        let date = Date()
        lastBackupDate = date
        lastError = nil
        UserDefaults.standard.set(date, forKey: StorageKeys.nostrMintBackupLastBackupDate)
    }

    func searchBackups(using mnemonic: String) async throws -> [DiscoveredNostrMintBackup] {
        guard SettingsManager.shared.useWebsockets else {
            throw NostrMintBackupError.webSocketsDisabled
        }
        guard let walletRepository else {
            throw NostrMintBackupError.notInitialized
        }
        let relays = normalizedRelays(SettingsManager.shared.nostrRelays)
        guard !relays.isEmpty else {
            throw NostrMintBackupError.noRelays
        }

        isSearching = true
        defer { isSearching = false }

        let backup = try await walletRepository.fetchMintBackup(
            relays: relays,
            options: RestoreOptions(timeoutSecs: 4)
        )

        let backupDate = Date(timeIntervalSince1970: TimeInterval(backup.timestamp))
        let discovered = backup.mints.map { mintUrl in
            DiscoveredNostrMintBackup(url: mintUrl.url, timestamp: backupDate, selected: true)
        }

        discoveredMints = discovered
        lastError = nil
        return discovered
    }

    func setSelected(_ selected: Bool, for mintURL: String) {
        guard let index = discoveredMints.firstIndex(where: { $0.url == mintURL }) else { return }
        discoveredMints[index].selected = selected
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

    private func normalizedRelays(_ relays: [String]) -> [String] {
        var seen = Set<String>()
        return relays.compactMap { relay in
            let trimmed = relay.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            guard lower.hasPrefix("wss://") || lower.hasPrefix("ws://") else { return nil }
            guard seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}

enum NostrMintBackupError: LocalizedError {
    case notInitialized
    case noRelays
    case webSocketsDisabled

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Wallet is not initialized."
        case .noRelays:
            return "No Nostr relays are configured."
        case .webSocketsDisabled:
            return "Websocket connections are disabled."
        }
    }
}
