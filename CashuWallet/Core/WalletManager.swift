import Foundation
import SwiftUI
import Combine
import CashuDevKit

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
    
    // MARK: - Services

    private let walletStore = WalletStore()
    
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
        getActiveMint: { [weak self] in self?.activeMint }
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
        bindServiceChanges()
    }

    private func bindServiceChanges() {
        [
            mintService.objectWillChange.eraseToAnyPublisher(),
            transactionService.objectWillChange.eraseToAnyPublisher(),
            tokenService.objectWillChange.eraseToAnyPublisher(),
            lightningService.objectWillChange.eraseToAnyPublisher()
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
            CashuDevKit.initLogging(level: "info")
            
            if let storedMnemonic = try keychainService.loadMnemonic() {
                mnemonic = storedMnemonic
                try await initializeWallet(mnemonic: storedMnemonic)
                needsOnboarding = false
            } else {
                needsOnboarding = true
            }
            isInitialized = true
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
        mnemonic = newMnemonic
        
        try keychainService.saveMnemonic(newMnemonic)
        try await initializeWallet(mnemonic: newMnemonic)
        
        // No default mint added - user must add mints manually
        // This avoids connection errors during wallet creation
        
        needsOnboarding = false
    }
    
    /// Restore wallet from mnemonic - Phase 1: Initialize wallet state
    /// After calling this, use restoreFromMint() to recover proofs via NUT-09,
    /// then call completeRestore() to finish onboarding.
    func initializeRestoredWallet(mnemonic: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let normalizedMnemonic = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.mnemonic = normalizedMnemonic

        try keychainService.saveMnemonic(normalizedMnemonic)
        try await initializeWallet(mnemonic: normalizedMnemonic)
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
        await mintService.ensureMintExists(url: normalizedUrl, name: mintName)

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
        await refreshBalance()
        await loadTransactions()
        needsOnboarding = false
    }

    /// Legacy restore for backward compatibility (initializes + completes without NUT-09)
    func restoreWallet(mnemonic: String) async throws {
        try await initializeRestoredWallet(mnemonic: mnemonic)
        await completeRestore()
    }
    
    private func initializeWallet(mnemonic: String) async throws {
        let databaseURL = try walletDatabaseURL()
        let repository = try initializeRepositoryWithRecovery(mnemonic: mnemonic, databaseURL: databaseURL)
        
        db = repository.db
        walletRepository = repository.repository
        
        await mintService.loadMints()
        await refreshBalance()
        await loadTransactions()
        await mintService.refreshMintInfo()

        initializeNostrKeypair(mnemonic: mnemonic)
        setupNPCQuoteListener()
    }
    
    private func generateMnemonic() throws -> String {
        // Use CDK's built-in BIP39 mnemonic generation
        return try CashuDevKit.generateMnemonic()
    }
    
    private func walletDatabaseURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        let walletDirectoryURL = applicationSupportURL.appendingPathComponent(walletDatabaseDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: walletDirectoryURL.path) {
            try FileManager.default.createDirectory(at: walletDirectoryURL, withIntermediateDirectories: true)
        }
        
        let currentDatabaseURL = walletDirectoryURL.appendingPathComponent(walletDatabaseFilename)
        try migrateLegacyWalletDatabaseIfNeeded(to: currentDatabaseURL)
        return currentDatabaseURL
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
    
    private func ensureMintTrackedForToken(_ tokenString: String) async throws {
        let token = try tokenService.decodeToken(tokenString: tokenString)
        let tokenMintUrl = try token.mintUrl().url
        await mintService.ensureMintExists(url: tokenMintUrl)
    }
    
    // MARK: - Nostr & NPC Integration
    
    private func initializeNostrKeypair(mnemonic: String) {
        Task {
            do {
                let seedData = Data(mnemonic.utf8).sha256()
                try NostrService.shared.deriveKeypair(from: seedData)
                try NPCService.shared.initializeWithSeed(seedData)
                await NPCService.shared.initializeIfEnabled()
            } catch {
                AppLogger.security.error("Failed to initialize Nostr keypair: \(error)")
            }
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
            Task {
                await self.mintNPCQuote(mintQuote: mintQuote)
            }
        }
    }
    
    private var processedQuotes: Set<String> = []
    
    func mintNPCQuote(mintQuote: MintQuote) async {
        guard !processedQuotes.contains(mintQuote.id) else { return }
        
        do {
            guard let walletRepository = walletRepository else {
                throw WalletError.notInitialized
            }
            
            let mintUrl = mintQuote.mintUrl
            await mintService.ensureMintExists(url: mintUrl.url)
            
            let wallet = try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)
            
            let proofs = try await wallet.mint(quoteId: mintQuote.id, amountSplitTarget: SplitTarget.none, spendingConditions: nil)
            let totalAmount = proofs.reduce(UInt64(0)) { $0 + $1.amount.value }
            
            processedQuotes.insert(mintQuote.id)
            
            await refreshBalance()
            await loadTransactions()
            
            NotificationCenter.default.post(
                name: .cashuTokenReceived,
                object: nil,
                userInfo: ["amount": totalAmount, "source": "npub.cash"]
            )
        } catch {
            let errorString = "\(error)"
            if errorString.contains("ISSUED") || errorString.contains("already") {
                processedQuotes.insert(mintQuote.id)
            }
            AppLogger.wallet.error("Failed to mint NPC quote: \(error)")
        }
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

    /// Fetch full mint info from the mint's API via CashuDevKit
    func fetchFullMintInfo(mintUrl: String) async throws -> CashuDevKit.MintInfo? {
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
        
        for mintUrlString in mintUrls {
            do {
                let mintUrl = MintUrl(url: mintUrlString)
                let wallet = try await walletRepository.getWallet(mintUrl: mintUrl, unit: .sat)
                let walletBalance = try await wallet.totalBalance()
                
                total += walletBalance.value
                mintService.updateMintBalance(url: mintUrlString, balance: walletBalance.value)
            } catch {
                mintService.updateMintBalance(url: mintUrlString, balance: 0)
                AppLogger.wallet.error("Failed to refresh balance for mint \(mintUrlString): \(error)")
            }
        }
        
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
    
    func createMeltQuote(request: String) async throws -> MeltQuoteInfo {
        return try await lightningService.createMeltQuote(request: request)
    }
    
    func createMeltQuote(invoice: String) async throws -> MeltQuoteInfo {
        return try await createMeltQuote(request: invoice)
    }

    func createHumanReadableMeltQuote(address: String, amount: UInt64) async throws -> MeltQuoteInfo {
        return try await lightningService.createHumanReadableMeltQuote(address: address, amount: amount)
    }

    func createOnchainMeltQuote(address: String, amount: UInt64) async throws -> MeltQuoteInfo {
        return try await lightningService.createOnchainMeltQuote(address: address, amount: amount)
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
    
    func meltTokens(quoteId: String) async throws -> String? {
        let preimage = try await lightningService.meltTokens(quoteId: quoteId)
        // Persist preimage as proof of payment
        if let preimage = preimage {
            transactionService.savePreimage(quoteId: quoteId, preimage: preimage)
        }
        AppLogger.wallet.info(
            "Melt quote \(quoteId, privacy: .public) returned from LightningService; refreshing wallet state"
        )
        await refreshBalance()
        await loadTransactions()
        return preimage
    }
    
    // MARK: - Token Operations (Delegate to TokenService)
    
    func sendTokens(amount: UInt64, memo: String? = nil, p2pkPubkey: String? = nil) async throws -> SendTokenResult {
        let result = try await tokenService.sendTokens(amount: amount, memo: memo, p2pkPubkey: p2pkPubkey)
        
        // Save pending token for tracking
        let tokenId = UUID().uuidString
        let pendingToken = PendingToken(
            tokenId: tokenId,
            token: result.token,
            amount: amount,
            fee: result.fee,
            date: Date(),
            mintUrl: activeMint?.url ?? "",
            memo: memo
        )
        transactionService.savePendingToken(pendingToken)
        
        await refreshBalance()
        await loadTransactions()
        
        return result
    }
    
    func receiveTokens(tokenString: String) async throws -> UInt64 {
        try await ensureMintTrackedForToken(tokenString)
        let amount = try await tokenService.receiveTokens(tokenString: tokenString)
        await refreshBalance()
        await loadTransactions()
        return amount
    }
    
    func decodeToken(tokenString: String) throws -> Token {
        return try tokenService.decodeToken(tokenString: tokenString)
    }
    
    func calculateReceiveFee(tokenString: String) async throws -> UInt64 {
        try await ensureMintTrackedForToken(tokenString)
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
            transactionService.removePendingToken(tokenId: pendingToken.tokenId)
        }
    }
    
    func checkAllPendingTokens() async {
        for token in pendingTokens {
            await checkPendingTokenStatus(pendingToken: token)
        }
        await loadTransactions()
    }

    func refreshPendingMintQuote(quoteId: String) async {
        let minted = await syncPendingMintQuote(
            quoteId: quoteId,
            allowPendingOnchainMintAttempt: true
        )
        if minted {
            await refreshBalance()
        }
        await loadTransactions()
    }

    func syncPendingMintQuotes() async {
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
    
    func loadTransactions() async {
        await transactionService.loadTransactions()
        objectWillChange.send()
    }

    @discardableResult
    private func syncPendingMintQuote(
        quoteId: String,
        allowPendingOnchainMintAttempt: Bool
    ) async -> Bool {
        guard !mintQuoteSyncsInFlight.contains(quoteId) else {
            AppLogger.wallet.info(
                "Skipping duplicate pending quote sync for \(quoteId, privacy: .public)"
            )
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
                let amount = try await lightningService.mintTokens(quoteId: quoteId)
                AppLogger.wallet.info(
                    "Minted pending quote \(quoteId, privacy: .public) for \(amount, privacy: .public) sats"
                )
                return true
            } catch {
                let errorString = error.localizedDescription.lowercased()
                if errorString.contains("issued") || errorString.contains("already") {
                    return true
                }

                if updatedQuote.paymentMethod == .onchain, updatedQuote.state == .pending {
                    AppLogger.wallet.info(
                        "Pending on-chain quote \(quoteId, privacy: .public) is not mintable yet: \(String(describing: error), privacy: .public)"
                    )
                    return false
                }

                AppLogger.wallet.error("Failed to mint pending quote \(quoteId): \(error)")
                return false
            }
        } catch {
            if isMissingQuoteError(error) {
                AppLogger.wallet.info(
                    "Pending quote \(quoteId, privacy: .public) is missing on the mint. Keeping the local pending entry for fallback checks."
                )
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
    
    // MARK: - Backup
    
    func getMnemonicWords() -> [String] {
        return mnemonic?.split(separator: " ").map(String.init) ?? []
    }
    
    func validateMnemonic(_ phrase: String) -> Bool {
        let words = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .map(String.init)
        guard words.count == 12 || words.count == 24 else { return false }
        return words.allSatisfy { bip39WordList.contains($0) }
    }

    /// Validate individual words and return which ones are invalid
    func invalidMnemonicWords(_ phrase: String) -> [Int] {
        let words = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .map(String.init)
        return words.enumerated().compactMap { index, word in
            bip39WordList.contains(word) ? nil : index
        }
    }
    
    deinit {
        if let npcQuoteObserver {
            NotificationCenter.default.removeObserver(npcQuoteObserver)
        }
    }
}

// MARK: - Error Types

enum WalletError: LocalizedError {
    case notInitialized
    case mintAlreadyExists
    case invalidMnemonic
    case insufficientBalance
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Wallet is not initialized"
        case .mintAlreadyExists:
            return "This mint is already added"
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .insufficientBalance:
            return "Insufficient balance"
        case .networkError(let message):
            return "Network error: \(message)"
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
    init(_ quoteState: CashuDevKit.QuoteState) {
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
    init(_ quoteState: CashuDevKit.QuoteState) {
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
