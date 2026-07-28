import Foundation
import Cdk
import os

private struct WalletLaunchRuntime: @unchecked Sendable {
    let db: WalletSqliteDatabase
    let repository: WalletRepository
}

private enum WalletStartupInstrumentation {
    static let signposter = OSSignposter(subsystem: "com.cashu.me", category: "wallet.startup")
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
            // Keychain I/O is synchronous. Read it away from the main actor so
            // the first SwiftUI frame is never held behind Security.framework.
            let storedMnemonic = try await Task.detached(priority: .userInitiated) {
                try KeychainService().loadMnemonic()
            }.value

            if let storedMnemonic {
                mnemonic = storedMnemonic
                loadCachedWalletState()
                needsOnboarding = ICloudRestorePolicy.needsOnboarding(
                    hasStoredMnemonic: true,
                    restoreIncomplete: hasIncompleteICloudRestore
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
                let directoryName = walletDatabaseDirectoryName
                let databaseFilename = walletDatabaseFilename
                let runtime = try await Task.detached(priority: .userInitiated) {
                    NSUbiquitousKeyValueStore.default.synchronize()
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
                needsOnboarding = ICloudRestorePolicy.needsOnboarding(
                    hasStoredMnemonic: false,
                    restoreIncomplete: hasIncompleteICloudRestore
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
        try await installCleanWallet(mnemonic: normalizedMnemonic)
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
        await mintService.ensureMintTracked(url: normalizedUrl, name: mintName)

        // Refresh balance after restore
        await refreshBalance()

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
        CashuRequestListener.shared.attach(walletManager: self)
        Task { await CashuRequestListener.shared.start() }
    }

    /// Legacy restore for backward compatibility (initializes + completes without NUT-09)
    func restoreWallet(mnemonic: String) async throws {
        try await initializeRestoredWallet(mnemonic: mnemonic)
        await completeRestore()
    }

    func deleteWallet() async throws {
        isLoading = true
        defer { isLoading = false }

        resetRuntimeState()
        try keychainService.deleteMnemonic()
        try? keychainService.deleteNostrPrivateKey()
        try removeWalletDatabaseFiles()
        walletStore.removeAllWalletData()
        SettingsManager.shared.resetWalletScopedData()
        NWCManager.shared.resetForWalletBoundary()
        CashuRequestStore.shared.resetForWalletBoundary()
        CashuRequestListener.shared.resetForWalletBoundary()
        MintLogoCache.shared.clear()
        processedQuotes.removeAll()
        // iCloud backup survives a local deletion — the user can restore it from
        // Restore Wallet → Restore from iCloud.
        needsOnboarding = true
        isInitialized = true
        isRuntimeReady = true
        SentryService.breadcrumb("Wallet deleted", category: "wallet.lifecycle")
    }

    private struct UserDefaultsSnapshot {
        let keys: Set<String>
        let values: [String: Any]
    }

    private struct WalletFileBackup {
        let originalURL: URL
        let backupURL: URL
    }

    private func installCleanWallet(mnemonic newMnemonic: String) async throws {
        let previousMnemonic = mnemonic ?? (try? keychainService.loadMnemonic())
        let defaultsSnapshot = walletBoundaryDefaultsSnapshot()
        let fileBackups = try backupWalletDatabaseFiles()

        do {
            resetRuntimeState()
            removeWalletBoundaryDefaults(defaultsSnapshot)
            walletStore.removeAllWalletData()
            SettingsStore.shared.clearWalletScopedData()
            NostrService.shared.resetForWalletBoundary(deleteStoredKey: false)
            NPCService.shared.resetForWalletBoundary()
            NWCManager.shared.resetForWalletBoundary()
            CashuRequestStore.shared.resetForWalletBoundary()
            CashuRequestListener.shared.resetForWalletBoundary()
            SettingsStore.shared.clearWalletScopedData()

            try initializeWalletForCreation(mnemonic: newMnemonic)
            try keychainService.saveMnemonic(newMnemonic)
            mnemonic = newMnemonic
            SettingsManager.shared.resetWalletScopedData(resetRuntimeServices: false)
            try removeWalletFileBackups(fileBackups)
            if !IntegrationTestConfig.shouldUseDeterministicUIRuntime {
                performICloudBackup()
            }
        } catch {
            SentryService.capture(error)
            resetRuntimeState()
            restoreWalletBoundaryDefaults(defaultsSnapshot)
            CashuRequestStore.shared.reloadFromDefaults()
            try? removeWalletDatabaseFiles()
            try? restoreWalletFileBackups(fileBackups)

            if let previousMnemonic {
                mnemonic = previousMnemonic
                do {
                    try initializeWalletForLaunch(mnemonic: previousMnemonic)
                    startDeferredStartupMaintenance()
                } catch {
                    AppLogger.wallet.error("Failed to reopen previous wallet after replacement error: \(error)")
                }
            }

            throw error
        }
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
        mintQuoteSyncsInFlight.removeAll()
        mintQuoteCheckThrottle.removeAll()
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
        let legacyDatabaseURL = legacyWalletDatabaseURL()
        
        guard FileManager.default.fileExists(atPath: legacyDatabaseURL.path) else { return }
        guard !FileManager.default.fileExists(atPath: currentDatabaseURL.path) else { return }
        
        try FileManager.default.moveItem(at: legacyDatabaseURL, to: currentDatabaseURL)
        
        for suffix in ["-wal", "-shm", "-journal"] {
            let legacySidecarURL = URL(fileURLWithPath: legacyDatabaseURL.path + suffix)
            guard FileManager.default.fileExists(atPath: legacySidecarURL.path) else { continue }
            
            let currentSidecarURL = URL(fileURLWithPath: currentDatabaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: currentSidecarURL.path) {
                try FileManager.default.removeItem(at: currentSidecarURL)
            }
            try FileManager.default.moveItem(at: legacySidecarURL, to: currentSidecarURL)
        }
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

    private func backupWalletDatabaseFiles() throws -> [WalletFileBackup] {
        let fileManager = FileManager.default
        let timestamp = Int(Date().timeIntervalSince1970)
        var backups: [WalletFileBackup] = []

        for originalURL in try walletDatabaseBoundaryURLs() {
            guard fileManager.fileExists(atPath: originalURL.path) else { continue }

            let backupURL = originalURL.deletingLastPathComponent()
                .appendingPathComponent("\(originalURL.lastPathComponent).replacing.\(timestamp).\(UUID().uuidString)")

            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }

            try fileManager.moveItem(at: originalURL, to: backupURL)
            backups.append(WalletFileBackup(originalURL: originalURL, backupURL: backupURL))
        }

        return backups
    }

    private func restoreWalletFileBackups(_ backups: [WalletFileBackup]) throws {
        let fileManager = FileManager.default

        for backup in backups.reversed() {
            if fileManager.fileExists(atPath: backup.originalURL.path) {
                try fileManager.removeItem(at: backup.originalURL)
            }

            guard fileManager.fileExists(atPath: backup.backupURL.path) else { continue }
            try fileManager.moveItem(at: backup.backupURL, to: backup.originalURL)
        }
    }

    private func removeWalletFileBackups(_ backups: [WalletFileBackup]) throws {
        let fileManager = FileManager.default

        for backup in backups {
            guard fileManager.fileExists(atPath: backup.backupURL.path) else { continue }
            try fileManager.removeItem(at: backup.backupURL)
        }
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
        let database = try WalletSqliteDatabase(filePath: databaseURL.path)
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
        let database = try WalletSqliteDatabase(filePath: databaseURL.path)
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
        try fileManager.moveItem(at: legacyURL, to: databaseURL)

        for suffix in ["-wal", "-shm", "-journal"] {
            let legacySidecarURL = URL(fileURLWithPath: legacyURL.path + suffix)
            guard fileManager.fileExists(atPath: legacySidecarURL.path) else { continue }
            let currentSidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            if fileManager.fileExists(atPath: currentSidecarURL.path) {
                try fileManager.removeItem(at: currentSidecarURL)
            }
            try fileManager.moveItem(at: legacySidecarURL, to: currentSidecarURL)
        }
    }

    nonisolated private static func shouldRecoverLaunchDatabase(
        after error: Error,
        databaseURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return false }
        let description = String(describing: error).lowercased()
        return description.contains("sqlite")
            || description.contains("database")
            || description.contains("corrupt")
            || description.contains("malformed")
            || description.contains("walletdb")
    }

    nonisolated private static func backupLaunchDatabase(
        at databaseURL: URL,
        databaseFilename: String,
        fileManager: FileManager
    ) throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("\(databaseFilename).corrupt.\(timestamp)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.moveItem(at: databaseURL, to: backupURL)

        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: sidecarURL.path) else { continue }
            let backupSidecarURL = URL(fileURLWithPath: backupURL.path + suffix)
            if fileManager.fileExists(atPath: backupSidecarURL.path) {
                try fileManager.removeItem(at: backupSidecarURL)
            }
            try fileManager.moveItem(at: sidecarURL, to: backupSidecarURL)
        }
        return backupURL
    }

    private func shouldAttemptDatabaseRecovery(after error: Error, databaseURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return false
        }
        
        let errorDescription = String(describing: error).lowercased()
        return errorDescription.contains("sqlite")
            || errorDescription.contains("database")
            || errorDescription.contains("corrupt")
            || errorDescription.contains("malformed")
            || errorDescription.contains("walletdb")
    }

    private func backupCorruptedDatabase(at databaseURL: URL) throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("\(walletDatabaseFilename).corrupt.\(timestamp)")
        
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        
        try FileManager.default.moveItem(at: databaseURL, to: backupURL)
        
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecarURL.path) else { continue }
            
            let sidecarBackupURL = URL(fileURLWithPath: backupURL.path + suffix)
            if FileManager.default.fileExists(atPath: sidecarBackupURL.path) {
                try FileManager.default.removeItem(at: sidecarBackupURL)
            }
            try FileManager.default.moveItem(at: sidecarURL, to: sidecarBackupURL)
        }
        
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
        // runs on every launch. App-level wiring alone is not enough: the
        // scenePhase `.active` onChange is unreliable at cold launch (hence the
        // duplicated CashuRequestListener start), and the ContentView `.task`
        // chain parks behind `await CashuRequestListener.shared.start()` (a
        // Nostr connect that can hang), so anything queued after it may never
        // run. Guard-protected — the scenePhase handler only stops/restarts it.
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

            await NWCManager.shared.startIfEnabled()
            self.startupMaintenanceTask = nil
        }
    }

    /// Returns true when saga recovery changed local wallet state and balances
    /// should be read again.
    private func performBestEffortWalletStartupMaintenance() async -> Bool {
        guard let walletRepository else { return false }
        let mintUrls = trackedMintUrlsForWalletAccess()
        guard !mintUrls.isEmpty else { return false }

        let now = Date().timeIntervalSince1970
        let storedKeysetRefreshTimestamps = walletStore.loadMintKeysetRefreshTimestamps()
        var keysetRefreshTimestamps = storedKeysetRefreshTimestamps
            .filter { mintUrls.contains($0.key) }
        var timestampsChanged = keysetRefreshTimestamps != storedKeysetRefreshTimestamps
        var recoveredWalletState = false

        for mintUrlString in mintUrls {
            guard !Task.isCancelled else { break }
            do {
                let wallet = try await walletRepository.getWallet(
                    mintUrl: MintUrl(url: mintUrlString),
                    unit: .sat
                )
                if await recoverIncompleteSagasIfNeeded(wallet: wallet, mintUrl: mintUrlString) {
                    recoveredWalletState = true
                }
                if await refreshKeysetsIfNeeded(
                    wallet: wallet,
                    mintUrl: mintUrlString,
                    lastRefresh: keysetRefreshTimestamps[mintUrlString],
                    now: now
                ) {
                    keysetRefreshTimestamps[mintUrlString] = now
                    timestampsChanged = true
                }
            } catch {
                AppLogger.wallet.error(
                    "Wallet startup maintenance failed for mint \(mintUrlString, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }

        if timestampsChanged {
            walletStore.saveMintKeysetRefreshTimestamps(keysetRefreshTimestamps)
        }

        // Saga recovery above only single-polls async-accepted (NUT-05) melts and
        // skips them while still pending; re-arm their completion tracking here.
        // The mint-quote pass settles anything paid while the app was gone
        // (Android startup parity) instead of waiting for the first poll tick.
        if !Task.isCancelled {
            await syncPendingMeltQuotes()
            await syncPendingMintQuotes()
        }
        return recoveredWalletState
    }

    private func recoverIncompleteSagasIfNeeded(wallet: Wallet, mintUrl: String) async -> Bool {
        do {
            let report = try await wallet.recoverIncompleteSagas()
            if report.recovered > 0 || report.compensated > 0 || report.skipped > 0 || report.failed > 0 {
                AppLogger.wallet.info(
                    "Recovered wallet sagas for mint \(mintUrl, privacy: .public): recovered=\(report.recovered, privacy: .public) compensated=\(report.compensated, privacy: .public) skipped=\(report.skipped, privacy: .public) failed=\(report.failed, privacy: .public)"
                )
            }
            return report.recovered > 0 || report.compensated > 0
        } catch {
            AppLogger.wallet.error(
                "Failed to recover wallet sagas for mint \(mintUrl, privacy: .public): \(String(describing: error), privacy: .public)"
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
            let keysets = try await wallet.refreshKeysets()
            AppLogger.wallet.info(
                "Refreshed \(keysets.count, privacy: .public) keysets for mint \(mintUrl, privacy: .public)"
            )
            return true
        } catch {
            AppLogger.wallet.error(
                "Failed to refresh keysets for mint \(mintUrl, privacy: .public): \(String(describing: error), privacy: .public)"
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
