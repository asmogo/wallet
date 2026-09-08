import Foundation

final class WalletStore {
    private let storage: StorageProtocol

    init(storage: StorageProtocol = UserDefaultsStorage()) {
        self.storage = storage
    }

    var activeMintURL: String? {
        get { value(forKey: StorageKeys.activeMintUrl) }
        set { setOptional(newValue, forKey: StorageKeys.activeMintUrl) }
    }

    func loadMints() -> [MintInfo] {
        let mints: [MintInfo] = value(forKey: StorageKeys.mints, legacyKeys: [StorageKeys.Legacy.mints]) ?? []
        let removed: [String] = value(forKey: StorageKeys.removedMintUrls) ?? []
        let removedIdentities = Set(removed.map(MintURLIdentity.normalized))
        return mints.filter { !removedIdentities.contains(MintURLIdentity.normalized($0.url)) }
    }

    func saveMints(_ mints: [MintInfo]) {
        set(mints, forKey: StorageKeys.mints)
    }

    /// CDK retains proofs after removal; they must not implicitly reconnect a mint.
    func isMintRemoved(url: String) -> Bool {
        let removed: [String] = value(forKey: StorageKeys.removedMintUrls) ?? []
        return removed.contains { MintURLIdentity.normalized($0) == MintURLIdentity.normalized(url) }
    }

    func setMintRemoved(url: String, removed: Bool) {
        let current: [String] = value(forKey: StorageKeys.removedMintUrls) ?? []
        let normalized = MintURLIdentity.normalized(url)
        var updated = current.filter { MintURLIdentity.normalized($0) != normalized }
        if removed { updated.append(normalized) }
        if updated != current { set(updated, forKey: StorageKeys.removedMintUrls) }
    }

    func loadBalancesByUnit() -> [String: UInt64] {
        value(forKey: StorageKeys.balancesByUnit) ?? [:]
    }

    func saveBalancesByUnit(_ balances: [String: UInt64]) {
        set(balances, forKey: StorageKeys.balancesByUnit)
    }

    func loadPendingReceiveTokens() -> [PendingReceiveToken] {
        value(
            forKey: StorageKeys.pendingReceiveTokens,
            legacyKeys: [StorageKeys.Legacy.pendingReceiveTokens]
        ) ?? []
    }

    func savePendingReceiveTokens(_ tokens: [PendingReceiveToken]) {
        set(tokens, forKey: StorageKeys.pendingReceiveTokens)
    }

    func loadCashuRequests() -> [CashuRequest] {
        value(forKey: StorageKeys.cashuRequests) ?? []
    }

    func loadSavedTokens() -> [String: String] {
        value(forKey: StorageKeys.savedTokens, legacyKeys: [StorageKeys.Legacy.savedTokens]) ?? [:]
    }

    func saveSavedTokens(_ tokens: [String: String]) {
        set(tokens, forKey: StorageKeys.savedTokens)
    }

    func loadPaymentPreimages() -> [String: String] {
        value(
            forKey: StorageKeys.paymentPreimages,
            legacyKeys: [StorageKeys.Legacy.paymentPreimages]
        ) ?? [:]
    }

    func savePaymentPreimages(_ preimages: [String: String]) {
        set(preimages, forKey: StorageKeys.paymentPreimages)
    }

    func loadMintQuoteTimestamps() -> [String: TimeInterval] {
        value(
            forKey: StorageKeys.mintQuoteTimestamps,
            legacyKeys: [StorageKeys.Legacy.mintQuoteTimestamps]
        ) ?? [:]
    }

    func saveMintQuoteTimestamps(_ timestamps: [String: TimeInterval]) {
        set(timestamps, forKey: StorageKeys.mintQuoteTimestamps)
    }

    func loadMintQuoteSchedules() -> [String: MintQuoteScheduleRecord] {
        value(forKey: StorageKeys.mintQuoteSchedules) ?? [:]
    }

    func saveMintQuoteSchedules(_ schedules: [String: MintQuoteScheduleRecord]) {
        set(schedules, forKey: StorageKeys.mintQuoteSchedules)
    }

    /// Last successful online keyset refresh per mint. Startup uses this to
    /// avoid contacting every configured mint on every app launch.
    func loadMintKeysetRefreshTimestamps() -> [String: TimeInterval] {
        value(forKey: StorageKeys.mintKeysetRefreshTimestamps) ?? [:]
    }

    func saveMintKeysetRefreshTimestamps(_ timestamps: [String: TimeInterval]) {
        set(timestamps, forKey: StorageKeys.mintKeysetRefreshTimestamps)
    }

    func loadProcessedNPCQuotes() -> [String] {
        value(forKey: StorageKeys.processedNPCQuotes) ?? []
    }

    func saveProcessedNPCQuotes(_ quoteIds: [String]) {
        set(quoteIds, forKey: StorageKeys.processedNPCQuotes)
    }

    func removeAllWalletData() {
        remove(keys: StorageKeys.walletDataKeys + StorageKeys.walletDataLegacyKeys)
        remove(keys: storage.keys(withPrefix: StorageKeys.walletDataPrefix))
    }

    /// One-way cleanup for stores obsoleted by the CDK 0.18 transaction
    /// lifecycle upgrade (local pending/claimed send records, async-melt
    /// tracking, melt fee notes, the old transaction cache). Idempotent.
    func purgeRetiredKeys() {
        remove(keys: StorageKeys.Retired.all)
    }

    private func value<T: Codable>(forKey key: String, legacyKeys: [String] = []) -> T? {
        if let value: T = try? storage.get(forKey: key) {
            return value
        }

        for legacyKey in legacyKeys {
            if let value: T = try? storage.get(forKey: legacyKey) {
                set(value, forKey: key)
                return value
            }
        }

        return nil
    }

    private func set<T: Codable>(_ value: T, forKey key: String) {
        do {
            try storage.set(value, forKey: key)
        } catch {
            AppLogger.wallet.error("Failed to save \(key): \(error)")
        }
    }

    private func setOptional<T: Codable>(_ value: T?, forKey key: String) {
        do {
            if let value {
                try storage.set(value, forKey: key)
            } else {
                try storage.remove(forKey: key)
            }
        } catch {
            AppLogger.wallet.error("Failed to update \(key): \(error)")
        }
    }

    private func remove(keys: [String]) {
        for key in Set(keys) {
            do {
                try storage.remove(forKey: key)
            } catch {
                AppLogger.wallet.error("Failed to remove \(key): \(error)")
            }
        }
    }
}
