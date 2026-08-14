import Foundation
import Cdk

/// Publishes the wallet's mint list as an encrypted NUT-27 backup on Nostr and
/// finds existing backups during restore. All protocol work (key derivation,
/// encryption, relay publishing) happens inside cdk via `WalletRepository`;
/// this service only adds settings gating, relay hygiene, and UI-facing state.
@MainActor
final class NostrMintBackupService: ObservableObject {
    static let shared = NostrMintBackupService()

    @Published private(set) var isBackingUp = false
    @Published private(set) var isSearching = false
    @Published private(set) var lastBackupDate: Date?

    /// Injected by `WalletManager` alongside its own repository lifecycle.
    var walletRepository: WalletRepository?

    private init() {
        lastBackupDate = UserDefaults.standard.object(forKey: StorageKeys.nostrMintBackupLastBackupDate) as? Date
    }

    /// Fire-and-forget trigger after mint-list changes — the Nostr twin of
    /// `performICloudBackup()`. Failures only log; the mint operation that
    /// triggered the backup must not surface a relay error.
    func backupCurrentMintsIfEnabled() async {
        guard SettingsManager.shared.nostrMintBackupEnabled else { return }
        do {
            try await backupMints()
        } catch NostrMintBackupError.nothingToBackUp {
            // Empty wallet — nothing worth publishing, not a failure.
        } catch {
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

        // NUT-27 backups are addressable events: publishing replaces the
        // previous backup for this seed on the relay. Never push an empty
        // list — a freshly initialized wallet (e.g. mid-restore) would
        // otherwise wipe the backup it is about to read.
        guard await !walletRepository.getWallets().isEmpty else {
            throw NostrMintBackupError.nothingToBackUp
        }

        isBackingUp = true
        defer { isBackingUp = false }

        _ = try await walletRepository.backupMints(
            relays: relays,
            options: BackupOptions(client: "cashu.me")
        )

        let date = Date()
        lastBackupDate = date
        UserDefaults.standard.set(date, forKey: StorageKeys.nostrMintBackupLastBackupDate)
    }

    /// Fetch the newest mint-list backup for the currently opened wallet seed.
    /// Returns the backed-up mint URLs (empty when the relays have no backup).
    func fetchBackedUpMintURLs() async throws -> [String] {
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

        do {
            let backup = try await walletRepository.fetchMintBackup(
                relays: relays,
                options: RestoreOptions(timeoutSecs: 4)
            )
            return backup.mints.map(\.url)
        } catch let error as FfiError {
            // CDK reports "no backup published for this seed" as an error
            // rather than an empty result. Fold it into the documented empty
            // return so call sites keep a single friendly "nothing found"
            // path instead of surfacing a raw FFI dump.
            if Self.isNoBackupFound(error) { return [] }
            throw error
        }
    }

    private static func isNoBackupFound(_ error: FfiError) -> Bool {
        let message: String
        switch error {
        case .Cdk(_, let errorMessage): message = errorMessage
        case .Internal(let errorMessage): message = errorMessage
        }
        return message.lowercased().contains("no backup event found")
    }

    func resetForWalletBoundary() {
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
    case nothingToBackUp

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Wallet is not initialized."
        case .noRelays:
            return "No Nostr relays are configured."
        case .webSocketsDisabled:
            return "Websocket connections are disabled."
        case .nothingToBackUp:
            return "There are no mints to back up yet."
        }
    }
}
