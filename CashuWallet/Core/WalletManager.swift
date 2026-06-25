import Foundation
import SwiftUI
import Combine
import Cdk

// MARK: - Wallet Manager

/// Central wallet coordinator that orchestrates all wallet operations.
/// Delegates to specialized services for specific functionality.
/// Views should observe this facade instead of individual services.
@MainActor
class WalletManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Total wallet balance in satoshis
    @Published var balance: UInt64 = 0
    
    /// Pending balance (invoices not yet claimed)
    @Published var pendingBalance: UInt64 = 0
    
    /// Whether the wallet is initialized
    @Published var isInitialized = false
    
    /// Whether the user needs to go through onboarding
    @Published var needsOnboarding = false
    
    /// Whether an operation is in progress
    @Published var isLoading = false
    
    /// Error message
    @Published var errorMessage: String?

    /// Active unit (sat, usd, etc.)
    @Published var activeUnit: String = "sat"

    private var mintQuoteSyncsInFlight: Set<String> = []

    /// Throttle state for passive mint-quote syncs (opening History, app
    /// foreground). Collapses overlapping triggers and rate-limits how often
    /// we re-poll the mint so reusable BOLT12 offers don't hammer it.
    private var isSyncingMintQuotes = false
    private var lastMintQuoteSyncAt: Date?
    private let mintQuoteSyncCooldown: TimeInterval = 45

    // MARK: - Services

    private let walletStore = WalletStore()
    private var processedQuotes: Set<String>
    private var npcQuotesInFlight: Set<String> = []
    
    /// Mint management service
    private(set) lazy var mintService = MintService(
        walletRepository: { [weak self] in self?.walletRepository },
        walletStore: walletStore
    )
    
    /// Transaction history service
    private(set) lazy var transactionService = TransactionService(
        walletRepository: { [weak self] in self?.walletRepository },
        walletDatabase: { [weak self] in self?.db },
        getTrackedMintUrls: { [weak self] in
            guard let self else { return [] }
            return self.trackedMintUrlsForWalletAccess()
        },
        walletStore: walletStore
    )
    
    /// Token operations service
    private(set) lazy var tokenService = TokenService(
        walletRepository: { [weak self] in self?.walletRepository },
        getActiveMint: { [weak self] in self?.activeMint }
    )
    
    /// Lightning operations service
    private(set) lazy var lightningService = LightningService(
        walletRepository: { [weak self] in self?.walletRepository },
        walletDatabase: { [weak self] in self?.db },
        getActiveMint: { [weak self] in self?.activeMint },
        getMints: { [weak self] in self?.mints ?? [] }
    )
    
    // MARK: - Computed Properties (Delegate to Services)
    
    /// List of configured mints
    var mints: [MintInfo] {
        get { mintService.mints }
        set { mintService.mints = newValue }
    }
    
    /// Currently active mint
    var activeMint: MintInfo? {
        get { mintService.activeMint }
        set { mintService.activeMint = newValue }
    }
    
    /// All wallet transactions
    var transactions: [WalletTransaction] {
        transactionService.transactions
    }
    
    /// Pending tokens (sent but not yet claimed)
    var pendingTokens: [PendingToken] {
        transactionService.pendingTokens
    }
    
    /// Pending receive tokens
    var pendingReceiveTokens: [PendingReceiveToken] {
        transactionService.pendingReceiveTokens
    }
    
    // MARK: - Private Properties
    
    private var walletRepository: WalletRepository?
    private var db: WalletSqliteDatabase?
    private let keychainService = KeychainService()
    // Note: No default mint is added on wallet creation - user must add mints manually
    private var mnemonic: String?
    private var hasInitialized = false
    private var npcQuoteObserver: NSObjectProtocol?
    private var serviceChangeCancellables: Set<AnyCancellable> = []
    private let walletDatabaseDirectoryName = "cashu-swift"
    private let walletDatabaseFilename = "wallet.db"
    
    // MARK: - Initialization
    
    init() {
        processedQuotes = Set(walletStore.loadProcessedNPCQuotes())
        bindServiceChanges()
    }

    private func bindServiceChanges() {
        [
            mintService.objectWillChange.eraseToAnyPublisher(),
            transactionService.objectWillChange.eraseToAnyPublisher()
        ]
        .forEach { publisher in
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.objectWillChange.send()
                    }
                }
                .store(in: &serviceChangeCancellables)
        }
    }
    
    // MARK: - Public Initialization
    
    /// Initialize the wallet - call this from App.task
    func initialize() async {
        guard !hasInitialized else { return }
        hasInitialized = true
        await loadWalletState()
    }
    
    private func loadWalletState() async {
        do {
            Cdk.initLogging(level: "info")
            
            if let storedMnemonic = try keychainService.loadMnemonic() {
                mnemonic = storedMnemonic
                try await initializeWalletForLaunch(mnemonic: storedMnemonic)
                needsOnboarding = false
                isInitialized = true
            } else {
                needsOnboarding = true
                isInitialized = true
            }
        } catch {
            AppLogger.wallet.error("Wallet initialization error: \(error)")
            isInitialized = true
            needsOnboarding = true
        }
    }
    
    // MARK: - Wallet Setup
    
    /// Create a new wallet with a fresh mnemonic
    func createNewWallet() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let newMnemonic = try generateMnemonic()
        try await installCleanWallet(mnemonic: newMnemonic)
        
        // No default mint added - user must add mints manually
        // This avoids connection errors during wallet creation
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

        return RestoreMintResult(
            mintUrl: normalizedUrl,
            mintName: mintName,
            spent: restored.spent.value,
            unspent: restored.unspent.value,
            pending: restored.pending.value
        )
    }

    /// Restore wallet from mnemonic - Phase 3: Complete restore and dismiss onboarding
    func completeRestore() async {
        completeOnboarding()
    }

    func completeOnboarding() {
        transactionService.loadCachedState()
        needsOnboarding = false
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
        processedQuotes.removeAll()
        needsOnboarding = true
        isInitialized = true
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
            SettingsStore.shared.clearWalletScopedData()

            try initializeWalletForCreation(mnemonic: newMnemonic)
            try keychainService.saveMnemonic(newMnemonic)
            mnemonic = newMnemonic
            SettingsManager.shared.resetWalletScopedData(resetRuntimeServices: false)
            try removeWalletFileBackups(fileBackups)
        } catch {
            resetRuntimeState()
            restoreWalletBoundaryDefaults(defaultsSnapshot)
            try? removeWalletDatabaseFiles()
            try? restoreWalletFileBackups(fileBackups)

            if let previousMnemonic {
                mnemonic = previousMnemonic
                try? await initializeWalletForLaunch(mnemonic: previousMnemonic)
            }

            throw error
        }
    }
    
    private func initializeWalletForLaunch(mnemonic: String) async throws {
        try initializeWalletRepository(mnemonic: mnemonic)

        mintService.loadCachedMints()
        await performBestEffortWalletStartupMaintenance()
        await refreshBalance()
        transactionService.loadCachedState()

        initializeNostrKeypairLocally(mnemonic: mnemonic)
        setupNPCQuoteListener()
    }

    private func initializeWalletForCreation(mnemonic: String) throws {
        try initializeWalletRepository(mnemonic: mnemonic)

        mintService.loadCachedMints()
        balance = mints.reduce(UInt64(0)) { $0 + $1.balance }
        transactionService.loadCachedState()

        initializeNostrKeypairLocally(mnemonic: mnemonic)
        setupNPCQuoteListener()
    }

    private func initializeWalletRepository(mnemonic: String) throws {
        let databaseURL = try walletDatabaseURL()
        let repository = try initializeRepositoryWithRecovery(mnemonic: mnemonic, databaseURL: databaseURL)
        
        db = repository.db
        walletRepository = repository.repository
        NostrMintBackupService.shared.walletRepository = repository.repository
        processedQuotes = Set(walletStore.loadProcessedNPCQuotes())
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
        if let npcQuoteObserver {
            NotificationCenter.default.removeObserver(npcQuoteObserver)
            self.npcQuoteObserver = nil
        }

        walletRepository = nil
        NostrMintBackupService.shared.walletRepository = nil
        db = nil
        mnemonic = nil
        balance = 0
        pendingBalance = 0
        activeUnit = "sat"
        errorMessage = nil
        mintQuoteSyncsInFlight.removeAll()
        npcQuotesInFlight.removeAll()
        processedQuotes.removeAll()
        mintService.clearState()
        transactionService.clearState()
        tokenService.clearState()
        lightningService.clearState()
    }
    
    private func generateMnemonic() throws -> String {
        // Use CDK's built-in BIP39 mnemonic generation
        return try Cdk.generateMnemonic()
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
    
    private func trackedMintUrlsForWalletAccess() -> [String] {
        var urls = mints.map(\.url).filter { !$0.isEmpty }
        
        if let activeUrl = activeMint?.url, !activeUrl.isEmpty, !urls.contains(activeUrl) {
            urls.append(activeUrl)
        }
        
        return Array(Set(urls))
    }

    private func performBestEffortWalletStartupMaintenance() async {
        guard let walletRepository else { return }
        let mintUrls = trackedMintUrlsForWalletAccess()
        guard !mintUrls.isEmpty else { return }

        for mintUrlString in mintUrls {
            do {
                let wallet = try await walletRepository.getWallet(
                    mintUrl: MintUrl(url: mintUrlString),
                    unit: .sat
                )
                await recoverIncompleteSagasIfNeeded(wallet: wallet, mintUrl: mintUrlString)
                await refreshKeysetsIfNeeded(wallet: wallet, mintUrl: mintUrlString)
            } catch {
                AppLogger.wallet.error(
                    "Wallet startup maintenance failed for mint \(mintUrlString, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func recoverIncompleteSagasIfNeeded(wallet: Wallet, mintUrl: String) async {
        do {
            let report = try await wallet.recoverIncompleteSagas()
            if report.recovered > 0 || report.compensated > 0 || report.skipped > 0 || report.failed > 0 {
                AppLogger.wallet.info(
                    "Recovered wallet sagas for mint \(mintUrl, privacy: .public): recovered=\(report.recovered, privacy: .public) compensated=\(report.compensated, privacy: .public) skipped=\(report.skipped, privacy: .public) failed=\(report.failed, privacy: .public)"
                )
            }
        } catch {
            AppLogger.wallet.error(
                "Failed to recover wallet sagas for mint \(mintUrl, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func refreshKeysetsIfNeeded(wallet: Wallet, mintUrl: String) async {
        do {
            let keysets = try await wallet.refreshKeysets()
            AppLogger.wallet.info(
                "Refreshed \(keysets.count, privacy: .public) keysets for mint \(mintUrl, privacy: .public)"
            )
        } catch {
            AppLogger.wallet.error(
                "Failed to refresh keysets for mint \(mintUrl, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
    
    private func ensureMintTrackedForToken(_ tokenString: String) async throws {
        let token = try tokenService.decodeToken(tokenString: tokenString)
        let tokenMintUrl = try token.mintUrl().url
        await mintService.ensureMintTracked(url: tokenMintUrl)
    }
    
    // MARK: - Nostr & NPC Integration

    @discardableResult
    private func initializeNostrKeypairLocally(mnemonic: String) -> Bool {
        do {
            let seedData = Data(mnemonic.utf8).sha256()
            try NostrService.shared.deriveKeypair(from: seedData)
            try NPCService.shared.initializeWithSeed(seedData)
            return true
        } catch {
            AppLogger.security.error("Failed to initialize Nostr keypair: \(error)")
            return false
        }
    }
    
    private func setupNPCQuoteListener() {
        if let npcQuoteObserver {
            NotificationCenter.default.removeObserver(npcQuoteObserver)
        }
        
        npcQuoteObserver = NotificationCenter.default.addObserver(forName: .npcQuoteReceived, object: nil, queue: .main) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let mintQuote = userInfo["mintQuote"] as? MintQuote else { return }
            let spendingConditions = userInfo["spendingConditions"] as? SpendingConditions
            Task {
                await self.mintNPCQuote(
                    mintQuote: mintQuote,
                    spendingConditions: spendingConditions
                )
            }
        }
    }
    
    func mintNPCQuote(
        mintQuote: MintQuote,
        spendingConditions: SpendingConditions? = nil
    ) async {
        guard !processedQuotes.contains(mintQuote.id),
              !npcQuotesInFlight.contains(mintQuote.id) else { return }

        npcQuotesInFlight.insert(mintQuote.id)
        defer {
            npcQuotesInFlight.remove(mintQuote.id)
        }
        
        do {
            guard let walletRepository = walletRepository else {
                throw WalletError.notInitialized
            }
            
            let mintUrl = mintQuote.mintUrl
            await mintService.ensureMintTracked(url: mintUrl.url)

            if let db {
                try await replaceStoredNPCMintQuote(mintQuote, in: db)
            }
            
            let wallet = try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)
            
            let proofs = try await wallet.mintUnified(
                quoteId: mintQuote.id,
                amountSplitTarget: SplitTarget.none,
                spendingConditions: spendingConditions
            )
            let totalAmount = proofs.reduce(UInt64(0)) { $0 + $1.amount.value }
            
            markNPCQuoteProcessed(mintQuote.id)
            
            await refreshBalance()
            await loadTransactions()
            
            NotificationCenter.default.post(
                name: .cashuTokenReceived,
                object: nil,
                userInfo: ["amount": totalAmount, "source": "npub.cash"]
            )
        } catch {
            if isAlreadyIssuedMintError(error) {
                markNPCQuoteProcessed(mintQuote.id)
            }
            AppLogger.wallet.error("Failed to mint NPC quote: \(error)")
        }
    }

    private func replaceStoredNPCMintQuote(
        _ quote: MintQuote,
        in walletDatabase: WalletSqliteDatabase
    ) async throws {
        do {
            try await walletDatabase.addMintQuote(quote: quote)
        } catch {
            try await walletDatabase.removeMintQuote(quoteId: quote.id)
            try await walletDatabase.addMintQuote(quote: quote)
        }
    }

    private func markNPCQuoteProcessed(_ quoteId: String) {
        processedQuotes.insert(quoteId)
        walletStore.saveProcessedNPCQuotes(processedQuotes.sorted())
    }
    
    // MARK: - Mint Operations (Delegate to MintService)
    
    func addMint(url: String) async throws {
        try await mintService.addMint(url: url)
        await refreshBalance()
    }
    
    func removeMint(at offsets: IndexSet) async {
        await mintService.removeMint(at: offsets)
        await refreshBalance()
    }
    
    func setActiveMint(_ mint: MintInfo) async throws {
        try await mintService.setActiveMint(mint)
        await refreshBalance()
    }

    /// Whether the given mint URL is already tracked by the wallet.
    func isMintKnown(url: String) -> Bool {
        mintService.isMintTracked(url: url)
    }


    func refreshMintInfo() async {
        await mintService.refreshMintInfo()
    }

    /// Fetch full mint info from the mint's API via CashuDevKit
    func fetchFullMintInfo(mintUrl: String) async throws -> Cdk.MintInfo? {
        guard let walletRepository = walletRepository else {
            throw WalletError.notInitialized
        }
        let mintUrlObj = MintUrl(url: mintUrl)
        let wallet = try await walletRepository.getWallet(mintUrl: mintUrlObj, unit: .sat)
        return try await wallet.fetchMintInfo()
    }

    // MARK: - Balance Operations
    
    func refreshBalance() async {
        guard let walletRepository = walletRepository else { return }
        let mintUrls = trackedMintUrlsForWalletAccess()
        
        guard !mintUrls.isEmpty else {
            balance = 0
            return
        }
        
        var total: UInt64 = 0
        var balancesByMintURL: [String: UInt64] = [:]
        
        for mintUrlString in mintUrls {
            do {
                let mintUrl = MintUrl(url: mintUrlString)
                let wallet = try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)
                let walletBalance = try await wallet.totalBalance()
                
                total += walletBalance.value
                balancesByMintURL[mintUrlString] = walletBalance.value
            } catch {
                balancesByMintURL[mintUrlString] = 0
                AppLogger.wallet.error("Failed to refresh balance for mint \(mintUrlString): \(error)")
            }
        }
        
        mintService.updateMintBalances(balancesByMintURL)
        balance = total
    }
    
    // MARK: - Lightning Operations (Delegate to LightningService)
    
    func createMintQuote(
        amount: UInt64?,
        method: PaymentMethodKind = .bolt11
    ) async throws -> MintQuoteInfo {
        let quote = try await lightningService.createMintQuote(amount: amount, method: method)
        await loadTransactions()
        return quote
    }

    func checkMintQuote(quoteId: String) async throws -> MintQuoteInfo {
        return try await lightningService.checkMintQuote(quoteId: quoteId)
    }
    
    func mintTokens(quoteId: String) async throws -> UInt64 {
        let amount = try await lightningService.mintTokens(quoteId: quoteId)
        await refreshBalance()
        await loadTransactions()
        return amount
    }

    /// Fire-and-forget: keep trying to mint a paid quote so a slow/transiently
    /// failing mint never blocks the receive sheet. `mintTokens` already
    /// refreshes balance + history on success, so the wallet credits the moment
    /// it lands; `syncPendingMintQuotes()` (History pull-to-refresh) is the
    /// ultimate backstop if all attempts here fail.
    func claimPaidMintQuote(quoteId: String) async {
        for _ in 0..<8 {
            do {
                _ = try await mintTokens(quoteId: quoteId)
                return
            } catch {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
        AppLogger.wallet.error("claimPaidMintQuote: gave up minting \(quoteId, privacy: .public)")
    }
    
    func createMeltQuote(
        request: String,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        try await lightningService.createMeltQuote(
            request: request,
            preferredMintURL: preferredMintURL
        )
    }
    
    func createMeltQuote(
        invoice: String,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        return try await createMeltQuote(request: invoice, preferredMintURL: preferredMintURL)
    }

    func createHumanReadableMeltQuote(
        address: String,
        amount: UInt64,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        try await lightningService.createHumanReadableMeltQuote(
            address: address,
            amount: amount,
            preferredMintURL: preferredMintURL
        )
    }

    func createOnchainMeltQuote(
        address: String,
        amount: UInt64,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        try await lightningService.createOnchainMeltQuote(
            address: address,
            amount: amount,
            preferredMintURL: preferredMintURL
        )
    }

    func subscribeToMintQuote(
        quoteId: String,
        paymentMethod: PaymentMethodKind
    ) async throws -> ActiveSubscription? {
        return try await lightningService.subscribeToMintQuote(
            quoteId: quoteId,
            paymentMethod: paymentMethod
        )
    }
    
    func meltTokens(quoteId: String, mintUrl: String? = nil) async throws -> MeltPaymentResult {
        let result = try await lightningService.meltTokens(quoteId: quoteId, mintUrl: mintUrl)
        // Persist preimage as proof of payment
        if let preimage = result.preimage {
            transactionService.savePreimage(quoteId: quoteId, preimage: preimage)
        }
        transactionService.saveMeltFeePaid(quoteId: quoteId, feePaid: result.feePaid)
        await refreshBalance()
        await loadTransactions()
        return result
    }

    // MARK: - Cashu Payment Requests

    func payCashuPaymentRequest(
        encoded: String,
        customAmountSats: UInt64? = nil,
        preferredMintURL: String? = nil
    ) async throws {
        let request = try PaymentRequestDecoder.parseCashuPaymentRequest(encoded)
        try await payCashuPaymentRequest(
            request,
            customAmountSats: customAmountSats,
            preferredMintURL: preferredMintURL
        )
    }

    func payCashuPaymentRequest(
        _ request: Cdk.PaymentRequest,
        customAmountSats: UInt64? = nil,
        preferredMintURL: String? = nil
    ) async throws {
        guard let walletRepository else {
            throw WalletError.notInitialized
        }

        if let unit = request.unit() {
            guard case .sat = unit else {
                throw NFCPaymentError.unsupportedUnit(PaymentRequestDecoder.unitDescription(unit))
            }
        }

        let requestedAmount = request.amount()?.value ?? customAmountSats
        guard let amount = requestedAmount, amount > 0 else {
            throw NFCPaymentError.noAmountSpecified
        }

        let selectedMint = try selectMint(
            forCashuPaymentRequest: request,
            amount: amount,
            preferredMintURL: preferredMintURL
        )
        let wallet = try await walletRepository.getWallet(mintUrl: MintUrl(url: selectedMint.url), unit: .sat)
        let customAmount = request.amount() == nil ? Amount(value: amount) : nil

        try await wallet.payRequest(paymentRequest: request, customAmount: customAmount)
        await refreshBalance()
        await loadTransactions()
    }

    private func selectMint(
        forCashuPaymentRequest request: Cdk.PaymentRequest,
        amount: UInt64,
        preferredMintURL: String?
    ) throws -> MintInfo {
        let requested = request.mints()
        let candidates: [MintInfo]

        if requested.isEmpty {
            candidates = mints
        } else {
            let requestedHosts = Set(requested.map(normalizedMintURL))
            candidates = mints.filter { requestedHosts.contains(normalizedMintURL($0.url)) }
        }

        guard !candidates.isEmpty else {
            throw NFCPaymentError.noMatchingMint(requestedMints: requested)
        }

        if let preferredMintURL,
           let preferredMint = candidates.first(where: {
               normalizedMintURL($0.url) == normalizedMintURL(preferredMintURL)
           }) {
            guard preferredMint.balance >= amount else {
                throw NFCPaymentError.insufficientBalance(required: amount, available: preferredMint.balance)
            }

            return preferredMint
        }

        if let activeMint,
           let preferredMint = candidates.first(where: {
               normalizedMintURL($0.url) == normalizedMintURL(activeMint.url)
           }),
           preferredMint.balance >= amount {
            return preferredMint
        }

        guard let selectedMint = candidates.first(where: { $0.balance >= amount }) else {
            let available = candidates.map(\.balance).max() ?? 0
            throw NFCPaymentError.insufficientBalance(required: amount, available: available)
        }

        return selectedMint
    }

    private func normalizedMintURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        var normalized = host
        if let port = url.port {
            normalized += ":\(port)"
        }
        normalized += url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized
    }
    
    // MARK: - Token Operations (Delegate to TokenService)
    
    func sendTokens(
        amount: UInt64,
        memo: String? = nil,
        p2pkPubkey: String? = nil,
        mintUrl preferredMintURL: String? = nil
    ) async throws -> SendTokenResult {
        let result = try await tokenService.sendTokens(
            amount: amount,
            memo: memo,
            p2pkPubkey: p2pkPubkey,
            mintUrl: preferredMintURL
        )
        let tokenMintURL = preferredMintURL ?? activeMint?.url ?? ""
        
        // Save pending token for tracking
        let tokenId = UUID().uuidString
        let pendingToken = PendingToken(
            tokenId: tokenId,
            token: result.token,
            amount: amount,
            fee: result.fee,
            date: Date(),
            mintUrl: tokenMintURL,
            memo: memo
        )
        transactionService.savePendingToken(pendingToken)
        
        await refreshBalance()
        await loadTransactions()
        
        return result
    }
    
    func receiveTokens(tokenString: String) async throws -> UInt64 {
        // Receive first: tokenService creates the CDK wallet and consumes the
        // keyset counter. Enriching the mint (createWallet/fetchMintInfo) before
        // this desyncs the counter and makes the mint reject "duplicate outputs"
        // on the first attempt. Track/enrich the mint only after a successful
        // receive, so an unredeemed token never adds the mint either.
        let amount = try await tokenService.receiveTokens(tokenString: tokenString)
        try? await ensureMintTrackedForToken(tokenString)
        await refreshBalance()
        await loadTransactions()
        return amount
    }

    /// Auto-claim a token that arrived via a NUT-18 Cashu Request, optionally attributing
    /// the payment to a specific request in CashuRequestStore.
    /// Identifies the CDK transaction id by diffing wallet.listTransactions() before
    /// and after the receive, then links it to the request so History can suppress
    /// the duplicate "Received ecash" row.
    @discardableResult
    func receiveCashuRequestPayment(tokenString: String, requestId: String?) async throws -> UInt64 {
        let beforeIds = await incomingTxIds(forTokenString: tokenString)
        let amount = try await receiveTokens(tokenString: tokenString)
        let afterIds = await incomingTxIds(forTokenString: tokenString)
        let newTxId = afterIds.subtracting(beforeIds).first

        if let requestId, let txId = newTxId {
            CashuRequestStore.shared.attachPayment(
                requestId: requestId,
                transactionId: txId,
                amount: amount
            )
        }

        var userInfo: [String: Any] = ["amount": amount, "source": "cashu-request"]
        if let requestId { userInfo["requestId"] = requestId }
        NotificationCenter.default.post(
            name: .cashuTokenReceived,
            object: nil,
            userInfo: userInfo
        )
        return amount
    }

    /// Lists incoming transaction ids for the mint encoded in a token string.
    /// Used by `receiveCashuRequestPayment` to identify the CDK tx id created by
    /// the receive. Returns an empty set on any failure so the diff degrades to
    /// "could not attribute payment" rather than crashing the receive.
    private func incomingTxIds(forTokenString tokenString: String) async -> Set<String> {
        guard let repo = walletRepository else { return [] }
        do {
            let token = try Token.decode(encodedToken: tokenString)
            let mintUrl = try token.mintUrl()
            let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
            let txs = try await wallet.listTransactions(direction: .incoming)
            return Set(txs.map { $0.id.hex })
        } catch {
            AppLogger.wallet.debug("incomingTxIds lookup failed: \(String(describing: error))")
            return []
        }
    }
    
    func decodeToken(tokenString: String) throws -> Token {
        return try tokenService.decodeToken(tokenString: tokenString)
    }
    
    func calculateReceiveFee(tokenString: String) async throws -> UInt64 {
        // Fee preview must not track/enrich the mint: doing so adds it to the
        // visible mint list (hiding the "new mint" badge on a later scan) and
        // disturbs the keyset counter before the receive. tokenService creates
        // the throwaway CDK wallet entry it needs for the calculation itself.
        return try await tokenService.calculateReceiveFee(tokenString: tokenString)
    }
    
    // MARK: - Pending Token Operations (Delegate to TransactionService)
    
    func savePendingToken(_ pendingToken: PendingToken) {
        transactionService.savePendingToken(pendingToken)
    }
    
    func loadPendingTokens() {
        transactionService.loadPendingTokens()
    }
    
    func removePendingToken(tokenId: String) {
        transactionService.removePendingToken(tokenId: tokenId)
    }
    
    func markTokenAsClaimed(token: String) async {
        transactionService.markTokenAsClaimed(token: token)
        await loadTransactions()
    }
    
    func savePendingReceiveToken(_ token: PendingReceiveToken) {
        transactionService.savePendingReceiveToken(token)
    }
    
    func loadPendingReceiveTokens() {
        transactionService.loadPendingReceiveTokens()
    }
    
    func removePendingReceiveToken(tokenId: String) {
        transactionService.removePendingReceiveToken(tokenId: tokenId)
    }
    
    func claimPendingReceiveToken(_ token: PendingReceiveToken) async throws -> UInt64 {
        let amount = try await receiveTokens(tokenString: token.token)
        transactionService.removePendingReceiveToken(tokenId: token.tokenId)
        await loadTransactions()
        return amount
    }
    
    func loadClaimedTokens() {
        transactionService.loadClaimedTokens()
    }
    
    // MARK: - Token Status Checks
    
    func checkTokenSpendable(token: String, mintUrl: String? = nil) async -> Bool {
        let resolvedMintUrl = mintUrl ?? activeMint?.url ?? ""
        guard !resolvedMintUrl.isEmpty else { return false }
        return await tokenService.checkTokenSpendable(token: token, mintUrl: resolvedMintUrl)
    }
    
    func checkPendingTokenStatus(pendingToken: PendingToken) async {
        let isSpent = await checkTokenSpendable(token: pendingToken.token, mintUrl: pendingToken.mintUrl)
        if isSpent {
            transactionService.markTokenAsClaimed(token: pendingToken.token)
        }
    }
    
    func checkAllPendingTokens() async {
        for token in pendingTokens {
            await checkPendingTokenStatus(pendingToken: token)
        }
        await loadTransactions()
    }

    /// Cooldown-gated sync for passive triggers (opening History, returning to
    /// foreground). Skips when a sync ran within `mintQuoteSyncCooldown`, so a
    /// paid offer settles on its own without re-polling the mint on every tab
    /// switch. Pull-to-refresh calls `syncPendingMintQuotes()` directly to
    /// bypass the cooldown (explicit user intent).
    func syncPendingMintQuotesIfStale() async {
        if let last = lastMintQuoteSyncAt,
           Date().timeIntervalSince(last) < mintQuoteSyncCooldown {
            return
        }
        await syncPendingMintQuotes()
    }

    func syncPendingMintQuotes() async {
        // Coarse in-flight guard: collapse overlapping triggers (e.g. opening
        // History while a foreground sync is already running) into one pass so
        // the full per-quote loop never runs twice concurrently.
        guard !isSyncingMintQuotes else { return }
        isSyncingMintQuotes = true
        lastMintQuoteSyncAt = Date()
        defer { isSyncingMintQuotes = false }

        guard let db else {
            await loadTransactions()
            return
        }

        var mintedAny = false

        do {
            let pendingQuotes = try await db.getUnissuedMintQuotes()
            for quote in pendingQuotes {
                let minted = await syncPendingMintQuote(
                    quoteId: quote.id,
                    allowPendingOnchainMintAttempt: false
                )
                mintedAny = mintedAny || minted
            }
        } catch {
            AppLogger.wallet.error("Failed to sync pending mint quotes: \(error)")
        }

        if mintedAny {
            await refreshBalance()
        }

        await loadTransactions()
    }
    
    func reclaimPendingToken(pendingToken: PendingToken) async throws -> UInt64 {
        let amount = try await receiveTokens(tokenString: pendingToken.token)
        transactionService.removePendingToken(tokenId: pendingToken.tokenId)
        await loadTransactions()
        return amount
    }
    
    // MARK: - Transaction History
    
    func loadTransactions(includeRemoteObservations: Bool = true) async {
        await transactionService.loadTransactions(includeRemoteObservations: includeRemoteObservations)
        objectWillChange.send()
    }

    @discardableResult
    private func syncPendingMintQuote(
        quoteId: String,
        allowPendingOnchainMintAttempt: Bool
    ) async -> Bool {
        guard !mintQuoteSyncsInFlight.contains(quoteId) else {
            return false
        }

        mintQuoteSyncsInFlight.insert(quoteId)
        defer {
            mintQuoteSyncsInFlight.remove(quoteId)
        }

        do {
            let updatedQuote = try await lightningService.checkMintQuote(quoteId: quoteId)

            guard updatedQuote.state == .paid
                || updatedQuote.state == .issued
                || (allowPendingOnchainMintAttempt && updatedQuote.paymentMethod == .onchain) else {
                return false
            }

            // BOLT12 quotes always appear in `getUnissuedMintQuotes()` because
            // CDK's SQL filter is `amount_issued = 0 OR payment_method = 'bolt12'`.
            // Skip them when nothing new has been paid since the last issuance,
            // otherwise every history refresh would re-trigger `mint_bolt12` and
            // could spawn duplicate transactions on any local/mint state drift.
            if updatedQuote.paymentMethod == .bolt12, let db {
                let storedQuote = try? await db.getMintQuote(quoteId: quoteId)
                if let storedQuote,
                   storedQuote.amountPaid.value > 0,
                   storedQuote.amountIssued.value >= storedQuote.amountPaid.value {
                    return false
                }
            }

            do {
                _ = try await lightningService.mintTokens(quoteId: quoteId)
                return true
            } catch {
                if isAlreadyIssuedMintError(error) {
                    return true
                }

                if updatedQuote.paymentMethod == .onchain, updatedQuote.state == .pending {
                    return false
                }

                AppLogger.wallet.error("Failed to mint pending quote \(quoteId): \(error)")
                return false
            }
        } catch {
            if isMissingQuoteError(error) {
                return false
            }
            AppLogger.wallet.error("Failed to refresh pending quote \(quoteId): \(error)")
            return false
        }
    }

    private func isMissingQuoteError(_ error: Error) -> Bool {
        if let walletError = error as? WalletError,
           case .networkError(let message) = walletError,
           message.localizedCaseInsensitiveContains("not found") {
            return true
        }

        return String(describing: error).localizedCaseInsensitiveContains("not found")
    }

    private func isAlreadyIssuedMintError(_ error: Error) -> Bool {
        let errorString = "\(error.localizedDescription) \(String(describing: error))".lowercased()

        if errorString.contains("already being minted")
            || errorString.contains("not issued")
            || errorString.contains("not yet")
            || errorString.contains("unissued") {
            return false
        }

        return errorString.contains("already issued")
            || errorString.contains("already minted")
            || errorString.contains("quote is issued")
            || errorString.contains("state=issued")
    }
    
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

    private func normalizeMnemonic(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
    
    deinit {
        if let npcQuoteObserver {
            NotificationCenter.default.removeObserver(npcQuoteObserver)
        }
    }
}

// MARK: - Error Types

enum WalletErrorMessage {
    static func message(for error: Error) -> String {
        if let walletError = error as? WalletError {
            return message(for: walletError)
        }

        if let ffiError = error as? Cdk.FfiError {
            return message(for: ffiError)
        }

        if let mappedMessage = message(forRawMessage: String(describing: error)) {
            return mappedMessage
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty,
           !looksLikeRawCDKError(description) {
            return description
        }

        let localizedDescription = error.localizedDescription
        if !localizedDescription.isEmpty,
           !looksLikeRawCDKError(localizedDescription),
           !localizedDescription.contains("Swift.Error error 1") {
            return localizedDescription
        }

        return "Something went wrong. Try again in a moment."
    }

    private static func message(for error: WalletError) -> String {
        switch error {
        case .notInitialized:
            return "The wallet is still starting up. Try again in a moment."
        case .mintAlreadyExists:
            return "This mint is already in your wallet."
        case .invalidMnemonic:
            return "That seed phrase doesn't look right. Check the spelling and try again."
        case .insufficientBalance:
            return "Not enough spendable ecash for this payment."
        case .networkError(let message):
            if let mappedMessage = self.message(forRawMessage: message) {
                return mappedMessage
            }

            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMessage.isEmpty,
               !looksLikeRawCDKError(trimmedMessage),
               !trimmedMessage.contains("Swift.Error error 1") {
                return trimmedMessage
            }

            return "The wallet could not complete that request. Try again in a moment."
        }
    }

    private static func message(for ffiError: Cdk.FfiError) -> String {
        switch ffiError {
        case .Cdk(let code, let errorMessage):
            return message(forCDKCode: code, rawMessage: errorMessage)
        case .Internal(let errorMessage):
            return message(forRawMessage: errorMessage)
                ?? "The wallet could not complete that request. Try again in a moment."
        }
    }

    private static func message(forCDKCode code: UInt32, rawMessage: String) -> String {
        switch code {
        case 10002:
            return "This token has already been processed by the mint."
        case 10003:
            return "This token could not be verified. Ask the sender for a new token."
        case 11001:
            return "This token was already redeemed."
        case 11002:
            return "The mint rejected this transaction because the amounts did not balance. Try again."
        case 11005:
            return "This mint does not support that unit."
        case 11006:
            return "This amount is outside the mint's allowed limits."
        case 11007:
            return "This token contains duplicate proofs and cannot be redeemed."
        case 11008:
            return "The mint rejected duplicate outputs. Try again."
        case 11009:
            return "This token mixes multiple units and cannot be redeemed here."
        case 11010:
            return "The token unit does not match this wallet action."
        case 11012:
            return "This token is still pending. Try again shortly."
        case 12001:
            return "This token uses an unknown keyset for this mint."
        case 12002:
            return "This mint no longer accepts this token's keyset."
        case 20000:
            return "The mint could not complete the Lightning payment. Try again or use another mint."
        case 20001:
            return "The invoice has not been paid yet."
        case 20002:
            return "Ecash has already been issued for this quote."
        case 20003:
            return "This mint has disabled receiving new ecash."
        case 20005:
            return "The payment is still pending. Try again shortly."
        case 20006:
            return "This invoice has already been paid."
        case 20007:
            return "This quote has expired. Create a new request."
        case 20008:
            return "The token lock signature is missing or invalid."
        case 30001:
            return "This mint requires authentication before this action."
        case 30002:
            return "Mint authentication failed. Check your mint credentials."
        case 31001:
            return "This mint requires blind authentication before this action."
        case 31002:
            return "Blind authentication failed. Check the mint and try again."
        default:
            return message(forRawMessage: rawMessage)
                ?? "The mint rejected the request. Try again or choose another mint."
        }
    }

    private static func message(forRawMessage rawMessage: String) -> String? {
        let message = extractedCDKMessage(from: rawMessage)
        let normalized = message.lowercased()

        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if normalized.contains("already being minted") {
            return "This payment is already being claimed. Give it a moment and refresh."
        }

        if normalized.contains("already issued")
            || normalized.contains("already minted")
            || normalized.contains("quote is issued")
            || normalized.contains("tokens already issued") {
            return "Ecash has already been issued for this quote."
        }

        if normalized.contains("already paid")
            || normalized.contains("request already paid")
            || normalized.contains("invoice already paid") {
            return "This invoice has already been paid."
        }

        if normalized.contains("not paid")
            || normalized.contains("unpaid quote")
            || normalized.contains("quote is not paid") {
            return "The invoice has not been paid yet."
        }

        if normalized.contains("not credited this on-chain quote yet")
            || (normalized.contains("not credited") && normalized.contains("on-chain")) {
            return "The mint has not credited this on-chain payment yet. Try again shortly."
        }

        if normalized.contains("pending quote")
            || normalized.contains("payment pending")
            || normalized.contains("quote pending") {
            return "The payment is still pending. Try again shortly."
        }

        if normalized.contains("expired quote")
            || normalized.contains("quote expired")
            || normalized.contains("invoice expired") {
            return "This quote has expired. Create a new request."
        }

        if normalized.contains("payment failed") {
            return "The payment failed. Try again or use another mint."
        }

        if normalized.contains("max fee exceeded")
            || normalized.contains("fee exceeded")
            || normalized.contains("fee is higher") {
            return "The fee is higher than the wallet limit for this payment."
        }

        if normalized.contains("insufficient")
            || normalized.contains("not enough")
            || normalized.contains("no spendable")
            || normalized.contains("no available proofs")
            || normalized.contains("balance too low") {
            return "Not enough spendable ecash for this payment."
        }

        if normalized.contains("token already spent")
            || normalized.contains("proof already used")
            || normalized.contains("already redeemed")
            || normalized.contains("proofs are spent") {
            return "This token was already redeemed."
        }

        if normalized.contains("token not verified")
            || normalized.contains("invalid proof")
            || normalized.contains("could not verify")
            || normalized.contains("dleq") {
            return "This token could not be verified. Ask the sender for a new token."
        }

        if normalized.contains("keyset not found")
            || normalized.contains("unknown keyset")
            || normalized.contains("keyset id not known") {
            return "This token uses an unknown keyset for this mint."
        }

        if normalized.contains("keyset inactive")
            || normalized.contains("inactive keyset") {
            return "This mint no longer accepts this token's keyset."
        }

        if normalized.contains("unsupported unit")
            || normalized.contains("unit unsupported") {
            return "This mint does not support that unit."
        }

        if normalized.contains("unsupported payment method")
            || normalized.contains("invalid payment method")
            || normalized.contains("payment method not supported") {
            return "This mint does not support that payment method."
        }

        if normalized.contains("no key for amount")
            || normalized.contains("amount key")
            || normalized.contains("no active keyset") {
            return "This mint cannot issue ecash for that amount right now."
        }

        if normalized.contains("amountless invoice")
            || normalized.contains("invoice amount undefined")
            || normalized.contains("amount is required") {
            return "This payment request does not include an amount."
        }

        if normalized.contains("amount out")
            || normalized.contains("outside of allowed")
            || normalized.contains("amount is outside") {
            return "This amount is outside the mint's allowed limits."
        }

        if normalized.contains("minting disabled") {
            return "This mint has disabled receiving new ecash."
        }

        if normalized.contains("melting disabled") {
            return "This mint has disabled payments."
        }

        if normalized.contains("clear auth required") {
            return "This mint requires authentication before this action."
        }

        if normalized.contains("clear auth failed") {
            return "Mint authentication failed. Check your mint credentials."
        }

        if normalized.contains("blind auth required") {
            return "This mint requires blind authentication before this action."
        }

        if normalized.contains("blind auth failed") {
            return "Blind authentication failed. Check the mint and try again."
        }

        if normalized.contains("no on-chain melt fee options") {
            return "This mint cannot quote an on-chain payment right now. Try another mint."
        }

        if normalized.contains("invalid payment request")
            || normalized.contains("invalid invoice")
            || (normalized.contains("bolt11") && normalized.contains("parse"))
            || (normalized.contains("bolt12") && normalized.contains("parse")) {
            return "This payment request does not look valid."
        }

        if normalized.contains("timeout")
            || normalized.contains("timed out") {
            return "The mint took too long to respond. Check your connection and try again."
        }

        if normalized.contains("network")
            || normalized.contains("http")
            || normalized.contains("connection")
            || normalized.contains("connect")
            || normalized.contains("dns")
            || normalized.contains("resolve")
            || normalized.contains("offline")
            || normalized.contains("tls")
            || normalized.contains("ssl")
            || normalized.contains("certificate")
            || normalized.contains("couldn't reach")
            || normalized.contains("could not reach") {
            return "Couldn't reach the mint. Check your connection and try again."
        }

        if normalized.contains("not found") {
            return "The mint could not find that quote. Create a new request and try again."
        }

        if normalized.contains("sqlite")
            || normalized.contains("database")
            || normalized.contains("corrupt")
            || normalized.contains("malformed") {
            return "The wallet database could not be opened. Restart the app and try again."
        }

        return nil
    }

    private static func extractedCDKMessage(from rawMessage: String) -> String {
        let keys = ["errorMessage: \"", "error_message: \"", "message: \""]
        for key in keys {
            guard let keyRange = rawMessage.range(of: key) else { continue }
            let remainder = rawMessage[keyRange.upperBound...]
            if let end = remainder.firstIndex(of: "\"") {
                return String(remainder[..<end])
            }
        }

        return rawMessage
    }

    private static func looksLikeRawCDKError(_ message: String) -> Bool {
        message.contains("FfiError")
            || message.contains("CashuDevKit")
            || message.contains("errorMessage:")
            || message.contains("CALL_ERROR")
    }
}

extension Error {
    var userFacingWalletMessage: String {
        WalletErrorMessage.message(for: self)
    }
}

enum WalletError: LocalizedError {
    case notInitialized
    case mintAlreadyExists
    case invalidMnemonic
    case insufficientBalance
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "The wallet is still starting up. Try again in a moment."
        case .mintAlreadyExists:
            return "This mint is already in your wallet."
        case .invalidMnemonic:
            return "That seed phrase doesn't look right. Check the spelling and try again."
        case .insufficientBalance:
            return "Not enough spendable ecash for this payment."
        case .networkError:
            return WalletErrorMessage.message(for: self)
        }
    }
}

// MARK: - Quote States

enum MintQuoteState {
    case pending
    case paid
    case issued
}

enum MeltQuoteState {
    case unpaid
    case pending
    case paid
}

extension MintQuoteState {
    init(_ quoteState: Cdk.QuoteState) {
        switch quoteState {
        case .paid:
            self = .paid
        case .issued:
            self = .issued
        case .unpaid, .pending:
            self = .pending
        }
    }
}

extension MeltQuoteState {
    init(_ quoteState: Cdk.QuoteState) {
        switch quoteState {
        case .unpaid:
            self = .unpaid
        case .pending:
            self = .pending
        case .paid, .issued:
            self = .paid
        }
    }
}
