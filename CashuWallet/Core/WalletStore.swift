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
        value(forKey: StorageKeys.mints, legacyKeys: [StorageKeys.Legacy.mints]) ?? []
    }

    func saveMints(_ mints: [MintInfo]) {
        set(mints, forKey: StorageKeys.mints)
    }

    func loadPendingTokens() -> [PendingToken] {
        value(forKey: StorageKeys.pendingTokens, legacyKeys: [StorageKeys.Legacy.pendingTokens]) ?? []
    }

    func savePendingTokens(_ tokens: [PendingToken]) {
        set(tokens, forKey: StorageKeys.pendingTokens)
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

    func loadClaimedTokens() -> [ClaimedToken] {
        value(forKey: StorageKeys.claimedTokens, legacyKeys: [StorageKeys.Legacy.claimedTokens]) ?? []
    }

    func saveClaimedTokens(_ tokens: [ClaimedToken]) {
        set(tokens, forKey: StorageKeys.claimedTokens)
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
}
