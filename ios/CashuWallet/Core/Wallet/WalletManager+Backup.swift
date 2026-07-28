import Foundation
import Cdk

struct ICloudBackupInfo: Sendable {
    /// May be empty: a seed in iCloud Keychain is a valid backup on its own. The
    /// mint list is convenience (which mints to auto re-add), not a requirement.
    let mintURLs: [String]
    let timestamp: Date
}

/// Result of a `performICloudBackup()` attempt, so the UI can report the truth
/// instead of an unconditional "Backed up ✓".
enum ICloudBackupOutcome: Equatable {
    case success(mintCount: Int)
    case deferred
    case unavailable
    case noSeed
    case failed(String)
}

enum ICloudRestoreState {
    private static let incompleteKey = "cashu.local.icloudRestoreIncomplete"

    static func isIncomplete(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: incompleteKey)
    }

    static func setIncomplete(
        _ incomplete: Bool,
        defaults: UserDefaults = .standard
    ) {
        if incomplete {
            defaults.set(true, forKey: incompleteKey)
        } else {
            defaults.removeObject(forKey: incompleteKey)
        }
    }
}

enum ICloudRestorePolicy {
    static func shouldPerformBackup(restoreIncomplete: Bool) -> Bool {
        !restoreIncomplete
    }

    static func needsOnboarding(
        hasStoredMnemonic: Bool,
        restoreIncomplete: Bool
    ) -> Bool {
        !hasStoredMnemonic || restoreIncomplete
    }
}

extension WalletManager {
    // MARK: - Backup

    func getMnemonicWords() -> [String] {
        return mnemonic?.split(separator: " ").map(String.init) ?? []
    }

    func validateMnemonic(_ phrase: String) -> Bool {
        let normalizedPhrase = normalizeMnemonic(phrase)
        let words = normalizedPhrase.split(separator: " ").map(String.init)
        guard words.count == 12 || words.count == 24 else { return false }
        guard words.allSatisfy({ bip39WordList.contains($0) }) else { return false }
        return (try? Cdk.mnemonicToEntropy(mnemonic: normalizedPhrase)) != nil
    }

    /// Validate individual words and return which ones are invalid
    func invalidMnemonicWords(_ phrase: String) -> [Int] {
        let words = normalizeMnemonic(phrase).split(separator: " ").map(String.init)
        return words.enumerated().compactMap { index, word in
            bip39WordList.contains(word) ? nil : index
        }
    }

    func normalizeMnemonic(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    // MARK: - iCloud Backup

    private enum ICloudKVKey {
        static let mintURLs = "cashu.icloud.mintURLs"
        static let timestamp = "cashu.icloud.backupTimestamp"
    }
    private static let iCloudEnabledKey = "cashu.local.icloudBackupEnabled"

    var iCloudBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.iCloudEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.iCloudEnabledKey)
            objectWillChange.send()
            if newValue {
                performICloudBackup()
            } else {
                clearICloudBackupData()
            }
        }
    }

    var hasIncompleteICloudRestore: Bool {
        ICloudRestoreState.isIncomplete()
    }

    func setICloudRestoreIncomplete(_ incomplete: Bool) {
        ICloudRestoreState.setIncomplete(incomplete)
        objectWillChange.send()
    }

    var lastICloudBackupDate: Date? {
        let ts = NSUbiquitousKeyValueStore.default.double(forKey: ICloudKVKey.timestamp)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    func iCloudAvailable() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func detectICloudBackup() -> ICloudBackupInfo? {
        guard keychainService.hasSynchronizableMnemonic() else {
            AppLogger.wallet.info("iCloud detect: no synchronizable seed → no backup")
            return nil
        }
        let store = NSUbiquitousKeyValueStore.default
        let urls = (store.array(forKey: ICloudKVKey.mintURLs) as? [String]) ?? []
        let ts = store.double(forKey: ICloudKVKey.timestamp)
        let timestamp = ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
        AppLogger.wallet.info("iCloud detect: seed present, \(urls.count) mint(s)")
        return ICloudBackupInfo(mintURLs: urls, timestamp: timestamp)
    }

    /// Off-main variant of `detectICloudBackup`, for the iCloud-restore screen's
    /// entrance. The keychain query (`SecItemCopyMatching`) and the KV-store
    /// `synchronize()` flush both block the calling thread; on the main actor
    /// they stall the crossfade into the screen. `KeychainService` is stateless
    /// (only immutable constants over the thread-safe Security framework), so a
    /// fresh instance inside a detached task keeps the work off the main thread
    /// with no shared-state hazard. `ICloudBackupInfo` is `Sendable`.
    nonisolated static func detectICloudBackupOffMain() async -> ICloudBackupInfo? {
        await Task.detached(priority: .userInitiated) {
            guard KeychainService().hasSynchronizableMnemonic() else {
                AppLogger.wallet.info("iCloud detect (off-main): no synchronizable seed → no backup")
                return nil
            }
            let store = NSUbiquitousKeyValueStore.default
            store.synchronize()
            let urls = (store.array(forKey: ICloudKVKey.mintURLs) as? [String]) ?? []
            let ts = store.double(forKey: ICloudKVKey.timestamp)
            let timestamp = ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
            AppLogger.wallet.info("iCloud detect (off-main): seed present, \(urls.count) mint(s)")
            return ICloudBackupInfo(mintURLs: urls, timestamp: timestamp)
        }.value
    }

    @discardableResult
    func performICloudBackup() -> ICloudBackupOutcome {
        guard ICloudRestorePolicy.shouldPerformBackup(
            restoreIncomplete: hasIncompleteICloudRestore
        ) else {
            AppLogger.wallet.info("iCloud backup deferred: wallet restore is incomplete")
            lastICloudBackupOutcome = .deferred
            return .deferred
        }
        guard iCloudBackupEnabled, iCloudAvailable() else {
            AppLogger.wallet.error("iCloud backup skipped: iCloud unavailable")
            lastICloudBackupOutcome = .unavailable
            return .unavailable
        }
        guard let currentMnemonic = mnemonic else {
            AppLogger.wallet.error("iCloud backup skipped: no seed in memory")
            lastICloudBackupOutcome = .noSeed
            return .noSeed
        }
        do {
            try keychainService.saveSynchronizableMnemonic(currentMnemonic)
            let store = NSUbiquitousKeyValueStore.default
            store.set(mints.map(\.url), forKey: ICloudKVKey.mintURLs)
            store.set(Date().timeIntervalSince1970, forKey: ICloudKVKey.timestamp)
            store.synchronize()
            objectWillChange.send()
            AppLogger.wallet.info("iCloud backup ok: \(self.mints.count) mint(s)")
            lastICloudBackupOutcome = .success(mintCount: mints.count)
            return .success(mintCount: mints.count)
        } catch {
            AppLogger.wallet.error("iCloud backup failed: \(error)")
            let message = error.userFacingWalletMessage
            lastICloudBackupOutcome = .failed(message)
            return .failed(message)
        }
    }

    func clearICloudBackupData() {
        try? keychainService.deleteSynchronizableMnemonic()
        let store = NSUbiquitousKeyValueStore.default
        store.removeObject(forKey: ICloudKVKey.mintURLs)
        store.removeObject(forKey: ICloudKVKey.timestamp)
        store.synchronize()
        UserDefaults.standard.removeObject(forKey: Self.iCloudEnabledKey)
        objectWillChange.send()
    }

    func restoreFromICloudBackup() async throws {
        guard let backup = detectICloudBackup() else {
            throw WalletError.networkError("No iCloud backup found.")
        }
        guard let recoveredMnemonic = try keychainService.loadSynchronizableMnemonic() else {
            throw WalletError.networkError("iCloud Keychain item is missing.")
        }
        AppLogger.wallet.info("iCloud restore: starting, \(backup.mintURLs.count) mint(s) to restore")

        // Keep the user's backup preference intact while independently
        // suppressing writes. Persist the marker so an interruption cannot make
        // a partial wallet look complete on the next launch.
        setICloudRestoreIncomplete(true)
        try await initializeRestoredWallet(mnemonic: recoveredMnemonic)

        var failedMintCount = 0
        for url in backup.mintURLs {
            do {
                _ = try await restoreFromMint(url: url)
            } catch {
                if error is CancellationError {
                    throw error
                }
                failedMintCount += 1
                AppLogger.wallet.error("iCloud restore: mint recovery failed for \(url): \(error)")
            }
        }

        guard failedMintCount == 0 else {
            AppLogger.wallet.error("iCloud restore: \(failedMintCount) mint(s) failed; preserving existing backup")
            throw WalletError.networkError(
                "Could not restore \(failedMintCount) of \(backup.mintURLs.count) mints. "
                    + "Your iCloud backup was preserved. Try again when all mints are reachable."
            )
        }

        // Only a complete restore may replace the backed-up mint list.
        setICloudRestoreIncomplete(false)
        iCloudBackupEnabled = true
        AppLogger.wallet.info("iCloud restore: complete, balance \(self.balance)")
    }
}
