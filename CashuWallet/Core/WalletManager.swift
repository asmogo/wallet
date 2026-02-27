import Foundation
import SwiftUI
import CashuDevKit

// MARK: - Wallet Manager

/// Central wallet coordinator that orchestrates all wallet operations.
/// Delegates to specialized services for specific functionality.
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
    
    // MARK: - Services
    
    /// Mint management service
    private(set) lazy var mintService = MintService(walletRepository: { [weak self] in self?.walletRepository })
    
    /// Transaction history service
    private(set) lazy var transactionService = TransactionService(walletRepository: { [weak self] in self?.walletRepository })
    
    /// Token operations service
    private(set) lazy var tokenService = TokenService(
        walletRepository: { [weak self] in self?.walletRepository },
        getActiveMint: { [weak self] in self?.activeMint }
    )
    
    /// Lightning operations service
    private(set) lazy var lightningService = LightningService(
        walletRepository: { [weak self] in self?.walletRepository },
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
    private let defaultMintUrl = "https://testnut.cashu.space"
    private var mnemonic: String?
    private var hasInitialized = false
    
    // MARK: - Initialization
    
    init() {
        // Empty init - wallet is initialized via initialize() called from App
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
            print("Wallet initialization error: \(error)")
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

        let mintUrl = try MintUrl(url: normalizedUrl)

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
        await transactionService.loadTransactions()
        needsOnboarding = false
    }

    /// Legacy restore for backward compatibility (initializes + completes without NUT-09)
    func restoreWallet(mnemonic: String) async throws {
        try await initializeRestoredWallet(mnemonic: mnemonic)
        await completeRestore()
    }
    
    private func initializeWallet(mnemonic: String) async throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbPath = documentsPath.appendingPathComponent("cashu_wallet.db").path
        
        db = try WalletSqliteDatabase(filePath: dbPath)
        walletRepository = try WalletRepository(mnemonic: mnemonic, db: db!)
        
        await mintService.loadMints()
        await refreshBalance()
        await transactionService.loadTransactions()
        
        initializeNostrKeypair(mnemonic: mnemonic)
        setupNPCQuoteListener()
    }
    
    private func generateMnemonic() throws -> String {
        // Use CDK's built-in BIP39 mnemonic generation
        return try CashuDevKit.generateMnemonic()
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
                print("Failed to initialize Nostr keypair: \(error)")
            }
        }
    }
    
    private func setupNPCQuoteListener() {
        NotificationCenter.default.addObserver(forName: .npcQuoteReceived, object: nil, queue: .main) { [weak self] notification in
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
            await transactionService.loadTransactions()
            
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
            print("Failed to mint NPC quote: \(error)")
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
    
    // MARK: - Balance Operations
    
    func refreshBalance() async {
        guard let walletRepository = walletRepository else { return }
        
        do {
            // Get all wallets and sum their balances
            let wallets = await walletRepository.getWallets()
            var total: UInt64 = 0
            
            for wallet in wallets {
                do {
                    // Only process sat unit wallets
                    guard wallet.unit() == .sat else { continue }
                    
                    let walletBalance = try await wallet.totalBalance()
                    let mintUrlStr = wallet.mintUrl().url
                    total += walletBalance.value
                    
                    // Update individual mint balance
                    mintService.updateMintBalance(url: mintUrlStr, balance: walletBalance.value)
                } catch {
                    print("Failed to get balance for wallet: \(error)")
                }
            }
            
            balance = total
        } catch {
            print("Failed to refresh balance: \(error)")
        }
    }
    
    // MARK: - Lightning Operations (Delegate to LightningService)
    
    func createMintQuote(amount: UInt64) async throws -> MintQuoteInfo {
        return try await lightningService.createMintQuote(amount: amount)
    }
    
    func mintTokens(quoteId: String) async throws -> UInt64 {
        let amount = try await lightningService.mintTokens(quoteId: quoteId)
        await refreshBalance()
        await transactionService.loadTransactions()
        return amount
    }
    
    func createMeltQuote(invoice: String) async throws -> MeltQuoteInfo {
        return try await lightningService.createMeltQuote(invoice: invoice)
    }
    
    func meltTokens(quoteId: String) async throws -> String? {
        let preimage = try await lightningService.meltTokens(quoteId: quoteId)
        await refreshBalance()
        await transactionService.loadTransactions()
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
        await transactionService.loadTransactions()
        
        return result
    }
    
    func receiveTokens(tokenString: String) async throws -> UInt64 {
        let amount = try await tokenService.receiveTokens(tokenString: tokenString)
        await refreshBalance()
        await transactionService.loadTransactions()
        return amount
    }
    
    func decodeToken(tokenString: String) throws -> Token {
        return try tokenService.decodeToken(tokenString: tokenString)
    }
    
    func calculateReceiveFee(tokenString: String) async throws -> UInt64 {
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
        await transactionService.loadTransactions()
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
        let amount = try await tokenService.receiveTokens(tokenString: token.token)
        transactionService.removePendingReceiveToken(tokenId: token.tokenId)
        await refreshBalance()
        await transactionService.loadTransactions()
        return amount
    }
    
    func loadClaimedTokens() {
        transactionService.loadClaimedTokens()
    }
    
    // MARK: - Token Status Checks
    
    func checkTokenSpendable(token: String) async -> Bool {
        return await tokenService.checkTokenSpendable(token: token, mintUrl: activeMint?.url ?? "")
    }
    
    func checkPendingTokenStatus(pendingToken: PendingToken) async {
        let isSpent = await checkTokenSpendable(token: pendingToken.token)
        if isSpent {
            transactionService.removePendingToken(tokenId: pendingToken.tokenId)
        }
    }
    
    func checkAllPendingTokens() async {
        for token in pendingTokens {
            await checkPendingTokenStatus(pendingToken: token)
        }
        await transactionService.loadTransactions()
    }
    
    func reclaimPendingToken(pendingToken: PendingToken) async throws -> UInt64 {
        let amount = try await tokenService.receiveTokens(tokenString: pendingToken.token)
        transactionService.removePendingToken(tokenId: pendingToken.tokenId)
        await refreshBalance()
        await transactionService.loadTransactions()
        return amount
    }
    
    // MARK: - Transaction History
    
    func loadTransactions() async {
        await transactionService.loadTransactions()
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
        return words.count == 12 || words.count == 24
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
