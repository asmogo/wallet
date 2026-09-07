import Foundation
import SQLite3
import Cdk
import os

private struct WalletLaunchRuntime: @unchecked Sendable {
    let db: WalletSqliteDatabase
    let repository: WalletRepository
}

private enum WalletStartupInstrumentation {
    static let signposter = OSSignposter(subsystem: "com.cashu.me", category: "wallet.startup")
}

struct WalletFileBackup: Equatable {
    let originalURL: URL
    let backupURL: URL
}

struct WalletReplacementFileOperations {
    let fileExists: (URL) -> Bool
    let moveItem: (URL, URL) throws -> Void
    let removeItem: (URL) throws -> Void

    static func using(_ fileManager: FileManager) -> WalletReplacementFileOperations {
        WalletReplacementFileOperations(
            fileExists: { fileManager.fileExists(atPath: $0.path) },
            moveItem: { try fileManager.moveItem(at: $0, to: $1) },
            removeItem: { try fileManager.removeItem(at: $0) }
        )
    }

    static let live = WalletReplacementFileOperations.using(.default)
}

enum WalletReplacementFiles {
    private struct StagedReplacement {
        let originalURL: URL
        let displacedURL: URL
    }

    static func backup(
        urls: [URL],
        operations: WalletReplacementFileOperations = .live,
        backupURL: (URL) -> URL
    ) throws -> [WalletFileBackup] {
        var backups: [WalletFileBackup] = []

        do {
            for originalURL in urls where operations.fileExists(originalURL) {
                let candidate = backupURL(originalURL)
                if operations.fileExists(candidate) {
                    try operations.removeItem(candidate)
                }

                let backup = WalletFileBackup(
                    originalURL: originalURL,
                    backupURL: candidate
                )
                do {
                    try operations.moveItem(originalURL, candidate)
                    backups.append(backup)
                } catch {
                    // A move implementation may report failure after the item
                    // reached its destination. Track the observed state so the
                    // current item participates in partial-backup rollback.
                    if operations.fileExists(candidate) {
                        backups.append(backup)
                    }
                    throw error
                }
            }
        } catch {
            for backup in backups.reversed() where operations.fileExists(backup.backupURL) {
                do {
                    if operations.fileExists(backup.originalURL) {
                        try operations.removeItem(backup.originalURL)
                    }
                    try operations.moveItem(backup.backupURL, backup.originalURL)
                } catch {
                    AppLogger.wallet.error("Failed to roll back a partial wallet database backup: \(error)")
                    SentryService.capture(error)
                }
            }
            throw error
        }

        return backups
    }

    static func restore(
        at urls: [URL],
        _ backups: [WalletFileBackup],
        operations: WalletReplacementFileOperations = .live,
        displacedURL: (URL) -> URL,
        beforeCommit: () throws -> Void = {},
        onRollback: () throws -> Void = {}
    ) throws {
        guard backups.allSatisfy({ operations.fileExists($0.backupURL) }) else {
            performExternalRollback(onRollback)
            throw CocoaError(.fileNoSuchFile)
        }

        let restorationOrder = Array(backups.reversed())
        var stagedReplacements: [StagedReplacement] = []
        let restorationURLs = uniqueURLs(urls + backups.map(\.originalURL))

        do {
            for originalURL in restorationURLs where operations.fileExists(originalURL) {
                let displaced = displacedURL(originalURL)
                if operations.fileExists(displaced) {
                    try operations.removeItem(displaced)
                }
                let replacement = StagedReplacement(
                    originalURL: originalURL,
                    displacedURL: displaced
                )
                do {
                    try operations.moveItem(originalURL, displaced)
                    stagedReplacements.append(replacement)
                } catch {
                    // Account for moves that completed before reporting an
                    // error, just as the backup-restoration phase does below.
                    if operations.fileExists(displaced) {
                        stagedReplacements.append(replacement)
                    }
                    throw error
                }
            }
        } catch {
            restoreStagedReplacements(stagedReplacements, operations: operations)
            performExternalRollback(onRollback)
            throw error
        }

        var restoredBackups: [WalletFileBackup] = []
        do {
            for backup in restorationOrder {
                do {
                    try operations.moveItem(backup.backupURL, backup.originalURL)
                    restoredBackups.append(backup)
                } catch {
                    // FileManager moves are atomic, but injected or future
                    // implementations may report failure after moving. Include
                    // that backup in state-based rollback when its live path
                    // appeared before the error surfaced.
                    if operations.fileExists(backup.originalURL) {
                        restoredBackups.append(backup)
                    }
                    throw error
                }
            }

            // Keep every replacement file displaced until the previous seed
            // has committed. If this throws, the catch below rolls the files
            // forward to the replacement wallet before compensating its seed.
            try beforeCommit()
        } catch {
            rollBackRestoredBackups(restoredBackups, operations: operations)
            restoreStagedReplacements(stagedReplacements, operations: operations)
            performExternalRollback(onRollback)
            throw error
        }

        for replacement in stagedReplacements where operations.fileExists(replacement.displacedURL) {
            do {
                try operations.removeItem(replacement.displacedURL)
            } catch {
                AppLogger.wallet.error("Failed to remove a displaced replacement database: \(error)")
                SentryService.capture(error)
            }
        }
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var paths: Set<String> = []
        return urls.filter { paths.insert($0.standardizedFileURL.path).inserted }
    }

    private static func rollBackRestoredBackups(
        _ backups: [WalletFileBackup],
        operations: WalletReplacementFileOperations
    ) {
        for backup in backups.reversed() where operations.fileExists(backup.originalURL) {
            do {
                if operations.fileExists(backup.backupURL) {
                    // A move implementation may have copied before throwing.
                    // The backup already survives, so remove only the restored
                    // live copy before putting the replacement back.
                    try operations.removeItem(backup.originalURL)
                } else {
                    try operations.moveItem(backup.originalURL, backup.backupURL)
                }
            } catch {
                AppLogger.wallet.error("Failed to roll back a restored wallet database backup: \(error)")
                SentryService.capture(error)
            }
        }
    }

    private static func restoreStagedReplacements(
        _ replacements: [StagedReplacement],
        operations: WalletReplacementFileOperations
    ) {
        for replacement in replacements.reversed()
        where operations.fileExists(replacement.displacedURL) {
            do {
                if operations.fileExists(replacement.originalURL) {
                    // A copy-style move may leave both paths present before
                    // throwing. The live replacement already survives.
                    try operations.removeItem(replacement.displacedURL)
                } else {
                    try operations.moveItem(replacement.displacedURL, replacement.originalURL)
                }
            } catch {
                AppLogger.wallet.error("Failed to restore a displaced replacement database: \(error)")
                SentryService.capture(error)
            }
        }
    }

    private static func performExternalRollback(_ rollback: () throws -> Void) {
        do {
            try rollback()
        } catch {
            AppLogger.wallet.error("Failed to restore the replacement wallet seed: \(error)")
            SentryService.capture(error)
        }
    }

    static func removeBackups(
        _ backups: [WalletFileBackup],
        operations: WalletReplacementFileOperations = .live
    ) throws {
        for backup in backups where operations.fileExists(backup.backupURL) {
            try operations.removeItem(backup.backupURL)
        }
    }
}

struct WalletFileMove: Equatable {
    let sourceURL: URL
    let destinationURL: URL
}

enum WalletFileMoves {
    private struct StagedDestination {
        let destinationURL: URL
        let displacedURL: URL
    }

    static func move(
        _ moves: [WalletFileMove],
        operations: WalletReplacementFileOperations = .live,
        displacedURL: (URL) -> URL
    ) throws {
        guard !moves.isEmpty else { return }
        try requireDistinctPaths(moves)
        guard moves.allSatisfy({ operations.fileExists($0.sourceURL) }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        var stagedDestinations: [StagedDestination] = []
        var completedMoves: [WalletFileMove] = []
        do {
            for move in moves where operations.fileExists(move.destinationURL) {
                let staged = StagedDestination(
                    destinationURL: move.destinationURL,
                    displacedURL: displacedURL(move.destinationURL)
                )
                if operations.fileExists(staged.displacedURL) {
                    try removeChecked(staged.displacedURL, operations: operations)
                }
                do {
                    try moveChecked(
                        staged.destinationURL,
                        staged.displacedURL,
                        operations: operations
                    )
                    stagedDestinations.append(staged)
                } catch {
                    if operations.fileExists(staged.displacedURL) {
                        stagedDestinations.append(staged)
                    }
                    throw error
                }
            }

            for move in moves {
                do {
                    try moveChecked(
                        move.sourceURL,
                        move.destinationURL,
                        operations: operations
                    )
                    completedMoves.append(move)
                } catch {
                    if operations.fileExists(move.destinationURL) {
                        completedMoves.append(move)
                    }
                    throw error
                }
            }
        } catch {
            rollBackMoves(completedMoves, operations: operations)
            restoreDestinations(stagedDestinations, operations: operations)
            throw error
        }

        for staged in stagedDestinations where operations.fileExists(staged.displacedURL) {
            do {
                try removeChecked(staged.displacedURL, operations: operations)
            } catch {
                AppLogger.wallet.error("Failed to remove a displaced wallet database destination: \(error)")
                SentryService.capture(error)
            }
        }
    }

    private static func requireDistinctPaths(_ moves: [WalletFileMove]) throws {
        let sources = moves.map { $0.sourceURL.standardizedFileURL.path }
        let destinations = moves.map { $0.destinationURL.standardizedFileURL.path }
        guard Set(sources).count == sources.count,
              Set(destinations).count == destinations.count,
              Set(sources).isDisjoint(with: Set(destinations)) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func rollBackMoves(
        _ moves: [WalletFileMove],
        operations: WalletReplacementFileOperations
    ) {
        for move in moves.reversed() where operations.fileExists(move.destinationURL) {
            do {
                if operations.fileExists(move.sourceURL) {
                    try removeChecked(move.destinationURL, operations: operations)
                } else {
                    try moveChecked(
                        move.destinationURL,
                        move.sourceURL,
                        operations: operations
                    )
                }
            } catch {
                AppLogger.wallet.error("Failed to roll back a wallet database move: \(error)")
                SentryService.capture(error)
            }
        }
    }

    private static func restoreDestinations(
        _ destinations: [StagedDestination],
        operations: WalletReplacementFileOperations
    ) {
        for staged in destinations.reversed() where operations.fileExists(staged.displacedURL) {
            do {
                if !operations.fileExists(staged.destinationURL) {
                    try moveChecked(
                        staged.displacedURL,
                        staged.destinationURL,
                        operations: operations
                    )
                }
            } catch {
                AppLogger.wallet.error("Failed to restore a displaced wallet database destination: \(error)")
                SentryService.capture(error)
            }
        }
    }

    private static func moveChecked(
        _ sourceURL: URL,
        _ destinationURL: URL,
        operations: WalletReplacementFileOperations
    ) throws {
        guard operations.fileExists(sourceURL), !operations.fileExists(destinationURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try operations.moveItem(sourceURL, destinationURL)
        guard !operations.fileExists(sourceURL), operations.fileExists(destinationURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func removeChecked(
        _ url: URL,
        operations: WalletReplacementFileOperations
    ) throws {
        try operations.removeItem(url)
        guard !operations.fileExists(url) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

private func walletMoveDisplacedURL(_ destinationURL: URL) -> URL {
    destinationURL.deletingLastPathComponent()
        .appendingPathComponent(
            "\(destinationURL.lastPathComponent).move-displaced.\(UUID().uuidString)"
        )
}

enum WalletMnemonicRollback {
    static func restore(
        previousMnemonic: String?,
        secureStorage: SecureStorageProtocol
    ) throws {
        if let previousMnemonic {
            try secureStorage.saveSecret(
                previousMnemonic,
                forKey: StorageKeys.Secure.mnemonic
            )
        } else {
            try secureStorage.deleteSecret(forKey: StorageKeys.Secure.mnemonic)
        }
    }
}

enum WalletStartupPolicy {
    /// Keysets are persisted by CDK. Refresh them periodically in the
    /// background instead of making every cold launch depend on every mint.
    static let keysetRefreshInterval: TimeInterval = 60 * 60

    static func shouldRefreshKeysets(
        lastRefresh: TimeInterval?,
        now: TimeInterval
    ) -> Bool {
        guard let lastRefresh else { return true }
        guard lastRefresh <= now else { return true }
        return now - lastRefresh >= keysetRefreshInterval
    }

    /// A CDK/database failure must not hide a complete wallet whose cached home
    /// model was already published. An interrupted iCloud restore is never
    /// complete, so it must return to recovery even when partial cache exists.
    static func needsOnboardingAfterRuntimeFailure(
        cachedWalletPublished: Bool,
        iCloudRestoreIncomplete: Bool = false
    ) -> Bool {
        iCloudRestoreIncomplete || !cachedWalletPublished
    }
}

enum WalletDatabaseRecoveryPolicy {
    // Moving the live database aside is safe only for definitive corruption signals.
    // Busy, I/O, permission, and generic open failures must preserve it for retry.
    private static let corruptionIndicators = [
        "sqlite_corrupt",
        "sqlite_notadb",
        "database disk image is malformed",
        "malformed database schema",
        "database disk image is corrupt",
        "file is not a database",
        "database corruption",
        "database is corrupt",
        "database is corrupted",
        "corrupt database",
    ]

    static func shouldRecover(errorDescription: String) -> Bool {
        let normalized = errorDescription.lowercased()
        return corruptionIndicators.contains(where: normalized.contains)
    }
}

extension WalletManager {
    // MARK: - Public Initialization

    /// Initialize the wallet - call this from App.task
    func initialize() async {
        guard !hasInitialized else { return }
        hasInitialized = true
        // UI-test support: wipe any persisted wallet so onboarding always shows
        // from a known-empty state. Driven by RESET_WALLET=1 in the test launch
        // environment; no effect in normal runs.
        if IntegrationTestConfig.shouldResetWallet {
            try? keychainService.deleteMnemonic()
            try? keychainService.deleteNostrPrivateKey()
            setICloudRestoreIncomplete(false)
            OnboardingCompletionState.clear()
            SettingsManager.shared.resetWalletScopedData()
        }

        if IntegrationTestConfig.shouldSeedWallet {
            do {
                try await installSeededUITestWallet()
                return
            } catch {
                AppLogger.wallet.error("Seeded UI-test wallet initialization error: \(error)")
            }
        }

        await loadWalletState()
    }

    /// Recover only missing Lightning-address prerequisites using the existing wallet.
    func retryLightningAddressSetup() async throws {
        try await LightningAddressSetupRecovery.retry(
            isRuntimeReady: { self.isRuntimeReady },
            initializeRuntime: { await self.loadWalletState() },
            isAddressInitialized: { NPCService.shared.isInitialized },
            loadSeed: {
                guard let mnemonic = try self.keychainService.loadMnemonic() else {
                    throw WalletError.notInitialized
                }
                return try Self.bip39Seed(mnemonic: mnemonic)
            },
            initializeAddress: { try NPCService.shared.initializeWithSeed($0) }
        )
    }

    private func loadWalletState() async {
        let signpostID = WalletStartupInstrumentation.signposter.makeSignpostID()
        let interval = WalletStartupInstrumentation.signposter.beginInterval(
            "WalletInitialize",
            id: signpostID
        )
        defer {
            WalletStartupInstrumentation.signposter.endInterval(
                "WalletInitialize",
                interval
            )
        }

        var publishedCachedWallet = false
        do {
            try await recoverWalletReplacement()
            // Keychain I/O is synchronous. Read it away from the main actor so
            // the first SwiftUI frame is never held behind Security.framework.
            let storedMnemonic = try await Task.detached(priority: .userInitiated) {
                try KeychainService().loadMnemonic()
            }.value

            if let storedMnemonic {
                mnemonic = storedMnemonic
                loadCachedWalletState()
                // Wallets installed before the completion marker existed are
                // treated as fully onboarded; only installs from this version
                // on can be incomplete.
                if !OnboardingCompletionState.hasMarker() {
                    OnboardingCompletionState.setCompleted(true)
                }
                needsOnboarding = ICloudRestorePolicy.needsOnboarding(
                    hasStoredMnemonic: true,
                    restoreIncomplete: hasIncompleteICloudRestore,
                    onboardingCompleted: OnboardingCompletionState.isCompleted()
                )
                isInitialized = true
                publishedCachedWallet = true
                WalletStartupInstrumentation.signposter.emitEvent(
                    "CachedHomeReady",
                    id: signpostID
                )

                // Opening WalletRepository is synchronous inside the CDK FFI
                // and may load wallets/fetch mint metadata. Keep the main actor
                // free while SwiftUI renders the cached balance and history.
                //
                // iCloud KVS sync is unrelated to the repository open, but on a
                // fully-cold process it's the first touch of the daemon since
                // launch and can stall on its IPC handshake. Run it as its own
                // task instead of sequencing it before the repository open, so
                // it never gates isRuntimeReady.
                let directoryName = walletDatabaseDirectoryName
                let databaseFilename = walletDatabaseFilename
                Task.detached(priority: .utility) {
                    NSUbiquitousKeyValueStore.default.synchronize()
                }
                let runtime = try await Task.detached(priority: .userInitiated) {
                    Cdk.initLogging(level: "info")
                    return try Self.prepareLaunchRuntime(
                        mnemonic: storedMnemonic,
                        directoryName: directoryName,
                        databaseFilename: databaseFilename
                    )
                }.value

                installLaunchRuntime(runtime, mnemonic: storedMnemonic)
                startDeferredStartupMaintenance()
                SentryService.breadcrumb("Wallet loaded", category: "wallet.lifecycle")
            } else {
                OnboardingCompletionState.clear()
                needsOnboarding = ICloudRestorePolicy.needsOnboarding(
                    hasStoredMnemonic: false,
                    restoreIncomplete: hasIncompleteICloudRestore,
                    onboardingCompleted: false
                )
                isRuntimeReady = true
                isInitialized = true
                // Neither cloud synchronization nor logging setup is required
                // to render or interact with onboarding.
                Task.detached(priority: .utility) {
                    NSUbiquitousKeyValueStore.default.synchronize()
                    Cdk.initLogging(level: "info")
                }
            }
        } catch {
            AppLogger.wallet.error("Wallet initialization error: \(error)")
            SentryService.capture(error)
            isInitialized = true
            isRuntimeReady = false
            errorMessage = error.localizedDescription
            // A runtime-open failure must not hide already-published balances
            // and history or incorrectly send an existing wallet to onboarding.
            needsOnboarding = WalletStartupPolicy.needsOnboardingAfterRuntimeFailure(
                cachedWalletPublished: publishedCachedWallet,
                iCloudRestoreIncomplete: hasIncompleteICloudRestore
            )
        }
    }

    private func loadCachedWalletState() {
        mintService.loadCachedMints()
        let cachedSatBalance = mints.reduce(UInt64(0)) { $0 + $1.balance }
        balance = cachedSatBalance
        var cachedUnitBalances = walletStore.loadBalancesByUnit()
        cachedUnitBalances["sat"] = cachedSatBalance
        balancesByUnit = cachedUnitBalances
        transactionService.loadCachedState()
    }

    private func installLaunchRuntime(_ runtime: WalletLaunchRuntime, mnemonic: String) {
        db = runtime.db
        walletRepository = runtime.repository
        NostrMintBackupService.shared.walletRepository = runtime.repository
        walletStore.purgeRetiredKeys()
        processedQuotes = Set(walletStore.loadProcessedNPCQuotes())
        initializeNostrKeypairLocally(mnemonic: mnemonic)
        setupNPCQuoteListener()
        isRuntimeReady = true
    }

    // MARK: - Wallet Setup

    /// Create a new wallet with a fresh mnemonic
    func createNewWallet() async throws {
        isLoading = true
        defer { isLoading = false }

        let newMnemonic = try generateMnemonic()
        try await installCleanWallet(mnemonic: newMnemonic)
        SentryService.breadcrumb("Wallet created", category: "wallet.lifecycle")
    }

    /// Restore wallet from mnemonic - Phase 1: Initialize wallet state
    /// After calling this, use restoreFromMint() to recover proofs via NUT-09,
    /// then call completeRestore() to finish onboarding.
    func initializeRestoredWallet(mnemonic: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let normalizedMnemonic = normalizeMnemonic(mnemonic)
        guard validateMnemonic(normalizedMnemonic) else {
            throw WalletError.invalidMnemonic
        }

        try proveWalletCanInitialize(mnemonic: normalizedMnemonic)
        try await installCleanWallet(mnemonic: normalizedMnemonic, restoring: true)
        SentryService.breadcrumb("Wallet restored from seed", category: "wallet.lifecycle")
    }

    /// Restore wallet from mnemonic - Phase 2: Recover proofs from a mint via NUT-09
    /// Returns the restore result with spent/unspent/pending amounts.
    func restoreFromMint(url: String) async throws -> RestoreMintResult {
        guard let walletRepository = walletRepository else {
            throw WalletError.notInitialized
        }

        let normalizedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return try await operationCoordinator.perform(
            kind: .restore,
            priority: .recovery,
            resourceID: normalizedUrl,
            protectsBackgroundExecution: true
        ) {
            let mintUrl = MintUrl(url: normalizedUrl)

            // Create wallet for this mint
            try await walletRepository.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)

            // Get the wallet instance
            let wallet = try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)

            // Fetch mint info for display name
            let info = try? await wallet.fetchMintInfo()
            let mintName = info?.name ?? "Unknown Mint"

            // Perform NUT-09 restore - this derives proofs from the seed and checks their state with the mint
            let restored = try await wallet.restore()

            // Ensure mint is in our saved list
            await self.mintService.ensureMintTracked(url: normalizedUrl, name: mintName)

            // Refresh balance while this restore still owns the repository.
            await self.refreshBalanceAssumingWalletOperationLease()

            SentryService.breadcrumb("Wallet restore from mint completed", category: "wallet.lifecycle")
            return RestoreMintResult(
                mintUrl: normalizedUrl,
                mintName: mintName,
                iconUrl: info?.iconUrl,
                spent: restored.spent.value,
                unspent: restored.unspent.value,
                pending: restored.pending.value
            )
        }
    }

    /// Restore wallet from mnemonic - Phase 3: Complete restore and dismiss onboarding
    func completeRestore() async {
        completeOnboarding()
        // The restored mint list is final now — refresh the Nostr backup with it.
        // (Must not run earlier: publishing while the repository is still empty
        // would replace the addressable backup event with an empty list.)
        Task { await NostrMintBackupService.shared.backupCurrentMintsIfEnabled() }
    }

    func completeOnboarding() {
        transactionService.loadCachedState()
        OnboardingCompletionState.setCompleted(true)
        if hasIncompleteICloudRestore {
            // Choosing a different onboarding path after an interrupted iCloud
            // restore is also a valid completion. Release the write barrier only
            // once that replacement wallet and its mint list are final.
            setICloudRestoreIncomplete(false)
            if iCloudBackupEnabled {
                performICloudBackup()
            }
        }
        needsOnboarding = false
        guard !IntegrationTestConfig.shouldUseDeterministicUIRuntime else { return }
        startDeferredStartupMaintenance()
        CashuRequestListener.shared.attach(walletManager: self)
        CashuRequestListener.shared.requestStart()
    }

    /// Legacy entry point. Mint recovery and explicit completion are still required.
    func restoreWallet(mnemonic: String) async throws {
        try await initializeRestoredWallet(mnemonic: mnemonic)
    }

    func deleteWallet() async throws {
        isLoading = true
        defer { isLoading = false }
        try lightningService.requireNoActiveMeltSettlement()

        // Stop accepting listener work and let an already-started token receive
        // finish all attribution/cache side effects before removing its wallet.
        await CashuRequestListener.shared.resetForWalletBoundary()
        await NWCManager.shared.stop()
        do {
            try await operationCoordinator.perform(kind: .recovery, priority: .recovery) {
                try lightningService.requireNoActiveMeltSettlement()
                await self.operationCoordinator.cancelPendingOperations()
                resetRuntimeState()
                try await recoverWalletReplacement()
                try keychainService.deleteMnemonic()
                try? keychainService.deleteNostrPrivateKey()
                OnboardingCompletionState.clear()
                try removeWalletDatabaseFiles()
                walletStore.removeAllWalletData()
                SettingsManager.shared.resetWalletScopedData()
                NWCManager.shared.resetForWalletBoundary()
                CashuRequestStore.shared.resetForWalletBoundary()
                MintLogoCache.shared.clear()
                processedQuotes.removeAll()
                // iCloud backup survives a local deletion — the user can restore it from
                // Restore Wallet → Restore from iCloud.
                needsOnboarding = true
                isInitialized = true
                isRuntimeReady = true
                SentryService.breadcrumb("Wallet deleted", category: "wallet.lifecycle")
            }
        } catch {
            await resumeServicesAfterWalletBoundaryFailure()
            throw error
        }
    }

    private struct UserDefaultsSnapshot {
        let keys: Set<String>
        let values: [String: Any]
    }

    private struct ReplacementState: Codable, Sendable {
        let mnemonic: String?
        let defaults: Data
        let secrets: [String: String]
    }

    private func recoverWalletReplacement() async throws {
        let urls = try walletDatabaseBoundaryURLs()
        let restored = try await Task.detached(priority: .userInitiated) {
            let storage = KeychainService()
            var restored = false
            try DurableWalletReplacement(storage: storage, urls: urls).recover { data in
                let state = try PropertyListDecoder().decode(ReplacementState.self, from: data)
                guard let snapshot = try PropertyListSerialization.propertyList(from: state.defaults, format: nil) as? [String: Any],
                      let keys = snapshot["keys"] as? [String], let values = snapshot["values"] as? [String: Any] else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try WalletMnemonicRollback.restore(previousMnemonic: state.mnemonic, secureStorage: storage)
                for (key, value) in state.secrets { try storage.saveSecret(value, forKey: key) }
                let defaults = UserDefaults.standard
                let currentKeys = defaults.dictionaryRepresentation().keys.filter {
                    $0.hasPrefix(StorageKeys.walletDataPrefix) || $0.hasPrefix(StorageKeys.npcDataPrefix)
                }
                for key in Set(StorageKeys.walletBoundaryKeys + currentKeys).union(keys) {
                    if let value = values[key] { defaults.set(value, forKey: key) }
                    else { defaults.removeObject(forKey: key) }
                }
                guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
                restored = true
            }
            return restored
        }.value
        if restored {
            SettingsManager.shared.reloadWalletScopedData()
            NWCManager.shared.reloadWalletScopedData()
            NPCService.shared.reloadWalletScopedData()
            CashuRequestStore.shared.reloadFromDefaults()
        }
    }

    private func installCleanWallet(mnemonic newMnemonic: String, restoring: Bool = false) async throws {
        try lightningService.requireNoActiveMeltSettlement()
        await CashuRequestListener.shared.resetForWalletBoundary()
        await NWCManager.shared.stop()
        do {
            try await operationCoordinator.perform(kind: .recovery, priority: .recovery) {
                // Recheck with the lease held: a payment could have started while
                // listener/NWC shutdown was suspended above.
                try lightningService.requireNoActiveMeltSettlement()
                await self.operationCoordinator.cancelPendingOperations()
                try await self.installCleanWalletAssumingLease(mnemonic: newMnemonic, restoring: restoring)
            }
        } catch {
            await resumeServicesAfterWalletBoundaryFailure()
            throw error
        }
    }

    private func resumeServicesAfterWalletBoundaryFailure() async {
        guard isRuntimeReady, walletRepository != nil else { return }
        resumeCashuRequestListenerAfterWalletBoundaryRollback()
        await NWCManager.shared.startIfEnabled()
    }

    private func installCleanWalletAssumingLease(mnemonic newMnemonic: String, restoring: Bool) async throws {
        try await recoverWalletReplacement()
        let previousMnemonic = try mnemonic ?? keychainService.loadMnemonic()
        let defaultsSnapshot = walletBoundaryDefaultsSnapshot()
        var secrets: [String: String] = [:]
        for key in SettingsManager.shared.walletReplacementSecretKeys {
            if let value = try keychainService.loadSecret(forKey: key) { secrets[key] = value }
        }
        let snapshot = ReplacementState(
            mnemonic: previousMnemonic,
            defaults: try PropertyListSerialization.data(
                fromPropertyList: ["keys": Array(defaultsSnapshot.keys), "values": defaultsSnapshot.values],
                format: .binary, options: 0
            ),
            secrets: secrets
        )
        let replacementURLs = try walletDatabaseBoundaryURLs()
        let snapshotData = try PropertyListEncoder().encode(snapshot)
        // Release CDK and its SQLite connection before copying any database files.
        resetRuntimeState()
        do {
            try await Task.detached(priority: .userInitiated) {
                try WalletReplacementCheckpoint.flushDatabases(in: replacementURLs)
                try DurableWalletReplacement(storage: KeychainService(), urls: replacementURLs).begin(state: snapshotData)
            }.value
            removeWalletBoundaryDefaults(defaultsSnapshot)
            walletStore.removeAllWalletData()
            SettingsStore.shared.clearWalletScopedData()
            // Applies to manual seed restores as well as iCloud restores, before
            // any operation can publish an empty/partial replacement backup.
            setICloudRestoreIncomplete(restoring)
            NostrService.shared.resetForWalletBoundary(deleteStoredKey: false)
            NPCService.shared.resetForWalletBoundary()
            NWCManager.shared.resetForWalletBoundary()
            CashuRequestStore.shared.resetForWalletBoundary()
            try initializeWalletForCreation(mnemonic: newMnemonic)
            try keychainService.saveMnemonic(newMnemonic)
            mnemonic = newMnemonic
            OnboardingCompletionState.setCompleted(false)
            SettingsManager.shared.resetWalletScopedData(resetRuntimeServices: false)
            guard UserDefaults.standard.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            try await Task.detached(priority: .userInitiated) {
                try DurableWalletReplacement(storage: KeychainService(), urls: replacementURLs).commit()
            }.value
        } catch {
            resetRuntimeState()
            do {
                try await recoverWalletReplacement()
                let recoveredMnemonic = try keychainService.loadMnemonic()
                mnemonic = recoveredMnemonic
                if let recoveredMnemonic {
                    try initializeWalletForLaunch(mnemonic: recoveredMnemonic)
                    startDeferredStartupMaintenance()
                    resumeCashuRequestListenerAfterWalletBoundaryRollback()
                } else {
                    needsOnboarding = true
                    isRuntimeReady = true
                }
            } catch {
                AppLogger.wallet.error("Previous wallet recovery must be retried at launch: \(error)")
                SentryService.capture(error)
            }
            throw error
        }
        // Cleanup failure leaves a committed journal that startup can safely finish.
        do { try await recoverWalletReplacement() }
        catch { AppLogger.wallet.error("Committed wallet recovery cleanup deferred: \(error)") }
        if !IntegrationTestConfig.shouldUseDeterministicUIRuntime { performICloudBackup() }
    }

    private func resumeCashuRequestListenerAfterWalletBoundaryRollback() {
        guard walletRepository != nil else { return }
        CashuRequestListener.shared.attach(walletManager: self)
        guard !IntegrationTestConfig.shouldUseDeterministicUIRuntime else { return }
        CashuRequestListener.shared.requestStart()
    }

    /// Open only local state needed for an immediately usable wallet. Network
    /// reconciliation is deliberately scheduled after `isInitialized` flips.
    private func initializeWalletForLaunch(mnemonic: String) throws {
        try initializeWalletRepository(mnemonic: mnemonic)
        loadCachedWalletState()
        initializeNostrKeypairLocally(mnemonic: mnemonic)
        setupNPCQuoteListener()
    }

    private func initializeWalletForCreation(mnemonic: String) throws {
        try initializeWalletRepository(mnemonic: mnemonic)

        mintService.loadCachedMints()
        balance = mints.reduce(UInt64(0)) { $0 + $1.balance }
        balancesByUnit = ["sat": balance]
        transactionService.loadCachedState()

        initializeNostrKeypairLocally(mnemonic: mnemonic)
        setupNPCQuoteListener()
    }

    private func installSeededUITestWallet() async throws {
        try await installCleanWallet(mnemonic: IntegrationTestConfig.seedMnemonic)
        installSeededUITestMintIfNeeded()
        completeOnboarding()
        isInitialized = true
    }

    private func installSeededUITestMintIfNeeded() {
        guard IntegrationTestConfig.shouldSeedMint,
              let rawURL = IntegrationTestConfig.seedMintURL,
              !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let normalizedURL = rawURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let mint = MintInfo(
            url: normalizedURL,
            name: "Cashu mint",
            description: "Seeded for UI tests",
            isActive: true,
            balance: 0,
            iconUrl: nil,
            units: ["sat"],
            supportedMintMethods: [.bolt11],
            supportedMeltMethods: [.bolt11],
            onchainMintConfirmations: nil,
            lastUpdated: Date()
        )

        mints = [mint]
        activeMint = mint
        mintService.saveMints()
    }

    private func initializeWalletRepository(mnemonic: String) throws {
        let databaseURL = try walletDatabaseURL()
        let repository = try initializeRepositoryWithRecovery(mnemonic: mnemonic, databaseURL: databaseURL)
        
        db = repository.db
        walletRepository = repository.repository
        NostrMintBackupService.shared.walletRepository = repository.repository
        processedQuotes = Set(walletStore.loadProcessedNPCQuotes())
        isRuntimeReady = true
    }

    private func proveWalletCanInitialize(mnemonic: String) throws {
        _ = try Cdk.mnemonicToEntropy(mnemonic: mnemonic)

        let fileManager = FileManager.default
        let temporaryDirectory = try temporaryWalletDirectoryURL()
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        let temporaryDatabaseURL = temporaryDirectory.appendingPathComponent(walletDatabaseFilename)
        _ = try createRepository(mnemonic: mnemonic, databaseURL: temporaryDatabaseURL)
    }

    private func resetRuntimeState() {
        stopPendingQuoteForegroundPolling()
        lastMintQuoteSyncAt = nil
        startupMaintenanceTask?.cancel()
        startupMaintenanceTask = nil

        if let npcQuoteObserver {
            NotificationCenter.default.removeObserver(npcQuoteObserver)
            self.npcQuoteObserver = nil
        }

        walletRepository = nil
        NostrMintBackupService.shared.walletRepository = nil
        db = nil
        isRuntimeReady = false
        mnemonic = nil
        balance = 0
        balancesByUnit = [:]
        pendingBalance = 0
        activeUnit = "sat"
        errorMessage = nil
        npcQuotesInFlight.removeAll()
        processedQuotes.removeAll()
        mintService.clearState()
        transactionService.clearState()
        tokenService.clearState()
        lightningService.clearState()
    }

    private func generateMnemonic() throws -> String {
        try Cdk.generateMnemonic()
    }

    private func walletDatabaseURL() throws -> URL {
        let walletDirectoryURL = try walletDirectoryURL(create: true)
        let currentDatabaseURL = walletDirectoryURL.appendingPathComponent(walletDatabaseFilename)
        try migrateLegacyWalletDatabaseIfNeeded(to: currentDatabaseURL)
        return currentDatabaseURL
    }

    private func applicationSupportURL(create: Bool = true) throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
    }

    private func walletDirectoryURL(create: Bool) throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        
        let walletDirectoryURL = applicationSupportURL.appendingPathComponent(walletDatabaseDirectoryName, isDirectory: true)
        if create && !FileManager.default.fileExists(atPath: walletDirectoryURL.path) {
            try FileManager.default.createDirectory(at: walletDirectoryURL, withIntermediateDirectories: true)
        }

        return walletDirectoryURL
    }

    private func temporaryWalletDirectoryURL() throws -> URL {
        let applicationSupportURL = try applicationSupportURL()
        return applicationSupportURL.appendingPathComponent(
            "\(walletDatabaseDirectoryName).restore.\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func legacyWalletDatabaseURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("cashu_wallet.db")
    }

    private func migrateLegacyWalletDatabaseIfNeeded(to currentDatabaseURL: URL) throws {
        try Self.migrateLegacyWalletDatabaseIfNeeded(
            from: legacyWalletDatabaseURL(),
            to: currentDatabaseURL,
            fileManager: .default
        )
    }

    private func walletBoundaryDefaultsSnapshot() -> UserDefaultsSnapshot {
        let defaults = UserDefaults.standard
        let prefixKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(StorageKeys.walletDataPrefix) || $0.hasPrefix(StorageKeys.npcDataPrefix)
        }
        let keys = Set(StorageKeys.walletBoundaryKeys + prefixKeys)
        var values: [String: Any] = [:]

        for key in keys {
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }

        return UserDefaultsSnapshot(keys: keys, values: values)
    }

    private func removeWalletBoundaryDefaults(_ snapshot: UserDefaultsSnapshot) {
        for key in snapshot.keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func restoreWalletBoundaryDefaults(_ snapshot: UserDefaultsSnapshot) {
        for key in snapshot.keys {
            if let value = snapshot.values[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private func walletDatabaseBoundaryURLs() throws -> [URL] {
        let walletDirectoryURL = try walletDirectoryURL(create: false)
        let legacyDatabaseURL = legacyWalletDatabaseURL()
        let legacySidecars = ["-wal", "-shm", "-journal"].map {
            URL(fileURLWithPath: legacyDatabaseURL.path + $0)
        }

        return [walletDirectoryURL, legacyDatabaseURL] + legacySidecars
    }

    private func removeWalletDatabaseFiles() throws {
        let fileManager = FileManager.default

        for url in try walletDatabaseBoundaryURLs() {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    private func initializeRepositoryWithRecovery(
        mnemonic: String,
        databaseURL: URL
    ) throws -> (db: WalletSqliteDatabase, repository: WalletRepository) {
        do {
            return try createRepository(mnemonic: mnemonic, databaseURL: databaseURL)
        } catch {
            guard shouldAttemptDatabaseRecovery(after: error, databaseURL: databaseURL) else {
                throw error
            }
            
            let backupURL = try backupCorruptedDatabase(at: databaseURL)
            AppLogger.wallet.info("Wallet DB recovery: moved corrupted database to \(backupURL.path)")
            return try createRepository(mnemonic: mnemonic, databaseURL: databaseURL)
        }
    }

    private func createRepository(
        mnemonic: String,
        databaseURL: URL
    ) throws -> (db: WalletSqliteDatabase, repository: WalletRepository) {
        let database = try LifecycleSafeWalletDatabase(filePath: databaseURL.path)
        let repository = try WalletRepository(
            mnemonic: mnemonic,
            store: customWalletStore(db: database)
        )
        return (database, repository)
    }

    nonisolated private static func prepareLaunchRuntime(
        mnemonic: String,
        directoryName: String,
        databaseFilename: String
    ) throws -> WalletLaunchRuntime {
        let fileManager = FileManager.default
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let walletDirectoryURL = applicationSupportURL.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        if !fileManager.fileExists(atPath: walletDirectoryURL.path) {
            try fileManager.createDirectory(
                at: walletDirectoryURL,
                withIntermediateDirectories: true
            )
        }

        let databaseURL = walletDirectoryURL.appendingPathComponent(databaseFilename)
        let legacyURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cashu_wallet.db")
        try migrateLegacyWalletDatabaseIfNeeded(
            from: legacyURL,
            to: databaseURL,
            fileManager: fileManager
        )

        do {
            return try createLaunchRuntime(mnemonic: mnemonic, databaseURL: databaseURL)
        } catch {
            guard shouldRecoverLaunchDatabase(
                after: error,
                databaseURL: databaseURL,
                fileManager: fileManager
            ) else {
                throw error
            }

            _ = try backupLaunchDatabase(
                at: databaseURL,
                databaseFilename: databaseFilename,
                fileManager: fileManager
            )
            AppLogger.wallet.info("Wallet DB recovery: moved corrupted launch database")
            return try createLaunchRuntime(mnemonic: mnemonic, databaseURL: databaseURL)
        }
    }

    nonisolated private static func createLaunchRuntime(
        mnemonic: String,
        databaseURL: URL
    ) throws -> WalletLaunchRuntime {
        let database = try LifecycleSafeWalletDatabase(filePath: databaseURL.path)
        let repository = try WalletRepository(
            mnemonic: mnemonic,
            store: customWalletStore(db: database)
        )
        return WalletLaunchRuntime(db: database, repository: repository)
    }

    nonisolated private static func migrateLegacyWalletDatabaseIfNeeded(
        from legacyURL: URL,
        to databaseURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        guard !fileManager.fileExists(atPath: databaseURL.path) else { return }
        var moves = [
            WalletFileMove(sourceURL: legacyURL, destinationURL: databaseURL)
        ]

        for suffix in ["-wal", "-shm", "-journal"] {
            let legacySidecarURL = URL(fileURLWithPath: legacyURL.path + suffix)
            guard fileManager.fileExists(atPath: legacySidecarURL.path) else { continue }
            let currentSidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            moves.append(
                WalletFileMove(
                    sourceURL: legacySidecarURL,
                    destinationURL: currentSidecarURL
                )
            )
        }

        try WalletFileMoves.move(
            moves,
            operations: .using(fileManager),
            displacedURL: walletMoveDisplacedURL
        )
    }

    nonisolated private static func shouldRecoverLaunchDatabase(
        after error: Error,
        databaseURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return false }
        return WalletDatabaseRecoveryPolicy.shouldRecover(
            errorDescription: String(describing: error)
        )
    }

    nonisolated private static func backupLaunchDatabase(
        at databaseURL: URL,
        databaseFilename: String,
        fileManager: FileManager
    ) throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("\(databaseFilename).corrupt.\(timestamp)")
        var moves = [
            WalletFileMove(sourceURL: databaseURL, destinationURL: backupURL)
        ]

        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: sidecarURL.path) else { continue }
            let backupSidecarURL = URL(fileURLWithPath: backupURL.path + suffix)
            moves.append(
                WalletFileMove(
                    sourceURL: sidecarURL,
                    destinationURL: backupSidecarURL
                )
            )
        }

        try WalletFileMoves.move(
            moves,
            operations: .using(fileManager),
            displacedURL: walletMoveDisplacedURL
        )
        return backupURL
    }

    private func shouldAttemptDatabaseRecovery(after error: Error, databaseURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return false
        }
        
        return WalletDatabaseRecoveryPolicy.shouldRecover(
            errorDescription: String(describing: error)
        )
    }

    private func backupCorruptedDatabase(at databaseURL: URL) throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("\(walletDatabaseFilename).corrupt.\(timestamp)")
        var moves = [
            WalletFileMove(sourceURL: databaseURL, destinationURL: backupURL)
        ]

        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecarURL.path) else { continue }
            let sidecarBackupURL = URL(fileURLWithPath: backupURL.path + suffix)
            moves.append(
                WalletFileMove(
                    sourceURL: sidecarURL,
                    destinationURL: sidecarBackupURL
                )
            )
        }

        try WalletFileMoves.move(
            moves,
            displacedURL: walletMoveDisplacedURL
        )
        return backupURL
    }

    func trackedMintUrlsForWalletAccess() -> [String] {
        var urls: [String] = []

        // Make the mint the user can act on first in every deferred pass.
        if let activeUrl = activeMint?.url, !activeUrl.isEmpty {
            urls.append(activeUrl)
        }

        for url in mints.map(\.url) where !url.isEmpty && !urls.contains(url) {
            urls.append(url)
        }

        return urls
    }

    private func startDeferredStartupMaintenance() {
        // Arm the foreground quote poll from the runtime path that provably
        // runs on every launch. App-level wiring alone is not enough because
        // scenePhase `.active` onChange is unreliable at cold launch.
        // Guard-protected — the scenePhase handler only stops/restarts it.
        startPendingQuoteForegroundPolling()
        guard startupMaintenanceTask == nil else { return }

        startupMaintenanceTask = Task(priority: .utility) { [weak self] in
            // Give SwiftUI a scheduling opportunity to replace LoadingView with
            // the cached wallet before any O(mints) CDK work begins.
            await Task.yield()
            guard let self, !Task.isCancelled else { return }

            // `totalBalance()` is local CDK state and can correct an app-cache
            // mismatch without requiring mint connectivity.
            await self.refreshBalance()
            guard !Task.isCancelled else { return }

            let recoveredWalletState = await self.performBestEffortWalletStartupMaintenance()
            guard !Task.isCancelled else { return }

            if recoveredWalletState {
                await self.refreshBalance()
            }
            guard !Task.isCancelled else { return }

            // These passive passes acquire only if the recovery lane is now
            // idle; they never queue stale polling behind a user payment.
            await self.syncPendingMeltQuotes()
            await self.syncPendingMintQuotes()
            guard !Task.isCancelled else { return }

            await NWCManager.shared.startIfEnabled()
            self.startupMaintenanceTask = nil
        }
    }

    /// Returns true when saga recovery changed local wallet state and balances
    /// should be read again.
    private func performBestEffortWalletStartupMaintenance() async -> Bool {
        do {
            return try await operationCoordinator.perform(
                kind: .recovery,
                priority: .recovery,
                protectsBackgroundExecution: true
            ) {
                await self.performBestEffortWalletStartupMaintenanceAssumingLease()
            }
        } catch {
            return false
        }
    }

    private func performBestEffortWalletStartupMaintenanceAssumingLease() async -> Bool {
        guard walletRepository != nil else { return false }
        let mintUrls = trackedMintUrlsForWalletAccess()
        guard !mintUrls.isEmpty else { return false }

        let now = Date().timeIntervalSince1970
        let storedKeysetRefreshTimestamps = walletStore.loadMintKeysetRefreshTimestamps()
        var keysetRefreshTimestamps = storedKeysetRefreshTimestamps
            .filter { mintUrls.contains($0.key) }
        var timestampsChanged = keysetRefreshTimestamps != storedKeysetRefreshTimestamps
        var recoveredWalletState = false

        let wallets = await trackedWalletsAssumingWalletOperationLease()
        for mintUrlString in mintUrls {
            guard !Task.isCancelled else { break }
            let mintWallets = wallets.filter {
                MintURLIdentity.normalized($0.mintUrl().url) == MintURLIdentity.normalized(mintUrlString)
            }
            var refreshedAllKeysets = !mintWallets.isEmpty
            for wallet in mintWallets {
                guard !Task.isCancelled else {
                    refreshedAllKeysets = false
                    break
                }
                if await recoverIncompleteSagasIfNeeded(wallet: wallet, mintUrl: mintUrlString) {
                    recoveredWalletState = true
                }
                let refreshed = await refreshKeysetsIfNeeded(
                    wallet: wallet,
                    mintUrl: mintUrlString,
                    lastRefresh: storedKeysetRefreshTimestamps[mintUrlString],
                    now: now
                )
                refreshedAllKeysets = refreshedAllKeysets && refreshed
            }
            if refreshedAllKeysets {
                keysetRefreshTimestamps[mintUrlString] = now
                timestampsChanged = true
            }
        }

        if timestampsChanged {
            walletStore.saveMintKeysetRefreshTimestamps(keysetRefreshTimestamps)
        }

        return recoveredWalletState
    }

    private func recoverIncompleteSagasIfNeeded(wallet: Wallet, mintUrl: String) async -> Bool {
        do {
            let beforeSagaCount = (try? await db?.getIncompleteSagas().count) ?? -1
            let beforeReservedBalance = (try? await wallet.totalReservedBalance().value) ?? UInt64.max
            let report = try await wallet.recoverIncompleteSagas()
            let afterSagaCount = (try? await db?.getIncompleteSagas().count) ?? -1
            let afterReservedBalance = (try? await wallet.totalReservedBalance().value) ?? UInt64.max
            if report.recovered > 0 || report.compensated > 0 || report.skipped > 0 || report.failed > 0 {
                AppLogger.wallet.info(
                    "wallet recovery resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintUrl), privacy: .public) recovered=\(report.recovered, privacy: .public) compensated=\(report.compensated, privacy: .public) skipped=\(report.skipped, privacy: .public) failed=\(report.failed, privacy: .public) sagas_before=\(beforeSagaCount, privacy: .public) sagas_after=\(afterSagaCount, privacy: .public) reserved_before=\(beforeReservedBalance, privacy: .public) reserved_after=\(afterReservedBalance, privacy: .public)"
                )
            }
            return report.recovered > 0 || report.compensated > 0
        } catch {
            AppLogger.wallet.error(
                "wallet recovery failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintUrl), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return false
        }
    }

    private func refreshKeysetsIfNeeded(
        wallet: Wallet,
        mintUrl: String,
        lastRefresh: TimeInterval?,
        now: TimeInterval
    ) async -> Bool {
        guard WalletStartupPolicy.shouldRefreshKeysets(lastRefresh: lastRefresh, now: now) else {
            return false
        }

        do {
            let keysets = try await wallet.keysets(policy: .refresh)
            AppLogger.wallet.info(
                "refreshed keysets count=\(keysets.count, privacy: .public) resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintUrl), privacy: .public)"
            )
            return true
        } catch {
            AppLogger.wallet.error(
                "keyset refresh failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintUrl), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return false
        }
    }

    func ensureMintTrackedForToken(_ tokenString: String) async throws {
        let token = try tokenService.decodeToken(tokenString: tokenString)
        let tokenMintUrl = try token.mintUrl().url
        await mintService.ensureMintTracked(url: tokenMintUrl)
    }
}


/// Crash recovery journal is kept in the device-only Keychain. Database backups remain
/// intact throughout replay; even an interrupted rollback can be repeated on the next launch.
struct DurableWalletReplacement {
    static let key = "wallet_replacement_journal_v1"
    private enum Phase: String, Codable { case preparing, installing, committed, restored }
    private struct Record: Codable {
        var phase: Phase
        let existed: [Bool]
        let state: Data
    }
    let storage: SecureStorageProtocol
    let urls: [URL]
    private var backups: [URL] { urls.map { URL(fileURLWithPath: $0.path + ".replacement-backup-v1") } }
    private let fm = FileManager.default

    private func read() throws -> Record? {
        guard let value = try storage.loadSecret(forKey: Self.key) else { return nil }
        guard let data = Data(base64Encoded: value) else { throw CocoaError(.fileReadCorruptFile) }
        return try PropertyListDecoder().decode(Record.self, from: data)
    }
    private func write(_ record: Record) throws {
        try storage.saveSecret(PropertyListEncoder().encode(record).base64EncodedString(), forKey: Self.key)
    }
    func begin(state: Data) throws {
        guard try read() == nil, backups.allSatisfy({ !fm.fileExists(atPath: $0.path) }) else {
            throw CocoaError(.fileWriteFileExists)
        }
        var record = Record(phase: .preparing, existed: urls.map { fm.fileExists(atPath: $0.path) }, state: state)
        try write(record)
        for i in urls.indices where record.existed[i] { try fm.copyItem(at: urls[i], to: backups[i]) }
        record.phase = .installing
        try write(record)
        for url in urls { try remove(url) }
    }
    func commit() throws {
        guard var record = try read(), record.phase == .installing else { throw CocoaError(.fileReadCorruptFile) }
        record.phase = .committed
        try write(record)
    }
    func recover(restoreState: (Data) throws -> Void) throws {
        guard var record = try read() else { return }
        guard record.existed.count == urls.count else { throw CocoaError(.fileReadCorruptFile) }
        if record.phase == .installing {
            guard urls.indices.allSatisfy({ !record.existed[$0] || fm.fileExists(atPath: backups[$0].path) }) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            for i in urls.indices {
                try remove(urls[i])
                if record.existed[i] { try fm.copyItem(at: backups[i], to: urls[i]) }
            }
            try restoreState(record.state)
            record.phase = .restored
            try write(record)
        }
        for backup in backups { try remove(backup) }
        try storage.deleteSecret(forKey: Self.key)
    }
    private func remove(_ url: URL) throws {
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }
}

/// Native FFI handles can be released asynchronously. A successful checkpoint
/// establishes a stable database image before the replacement journal copies it.
enum WalletReplacementCheckpoint {
    static func flushDatabases(in urls: [URL]) throws {
        for url in urls {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { continue }
            let candidates = directory.boolValue
                ? try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                : [url]
            for database in candidates where database.pathExtension == "db" || database.pathExtension == "sqlite" {
                try flush(database)
            }
        }
    }

    private static func flush(_ url: URL) throws {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA wal_checkpoint(TRUNCATE)", -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_int(statement, 0) == 0 else {
            throw WalletError.networkError("Wallet database is still busy. Try again in a moment.")
        }
    }
}
