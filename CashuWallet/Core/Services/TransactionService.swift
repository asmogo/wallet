import Foundation
import CashuDevKit

// MARK: - Transaction Service

/// Service responsible for transaction history and token persistence.
/// Handles loading, saving, and managing transaction records and pending tokens.
@MainActor
class TransactionService: ObservableObject {
    
    // MARK: - Published Properties
    
    /// All wallet transactions (incoming/outgoing)
    @Published var transactions: [WalletTransaction] = []
    
    /// Pending tokens that have been sent but not yet claimed by recipient
    @Published var pendingTokens: [PendingToken] = []
    
    /// Pending tokens that have been received but not yet claimed by user
    @Published var pendingReceiveTokens: [PendingReceiveToken] = []
    
    // MARK: - Private Properties
    
    private var claimedTokens: [ClaimedToken] = []
    private let walletRepository: () -> WalletRepository?
    private let getTrackedMintUrls: () -> [String]
    
    // Storage keys
    private enum StorageKeys {
        static let pendingTokens = "pendingTokens"
        static let pendingReceiveTokens = "pendingReceiveTokens"
        static let claimedTokens = "claimedTokens"
        static let savedTokens = "savedTokens"
    }
    
    // MARK: - Initialization
    
    init(
        walletRepository: @escaping () -> WalletRepository?,
        getTrackedMintUrls: @escaping () -> [String]
    ) {
        self.walletRepository = walletRepository
        self.getTrackedMintUrls = getTrackedMintUrls
    }
    
    // MARK: - Transaction Loading
    
    /// Load transaction history from all mints
    func loadTransactions() async {
        guard let repo = walletRepository() else { return }
        
        // Load pending and claimed tokens from storage
        loadPendingTokens()
        loadPendingReceiveTokens()
        loadClaimedTokens()
        
        // Get transactions from tracked wallets
        var allTransactions: [WalletTransaction] = []
        let trackedMintUrls = Set(getTrackedMintUrls().filter { !$0.isEmpty })
        
        for mintUrlString in trackedMintUrls {
            do {
                let mintUrl = try MintUrl(url: mintUrlString)
                let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
                let txs = try await wallet.listTransactions(direction: nil)
                let walletTxs: [WalletTransaction] = txs.map { tx in
                    // Determine if this is a Lightning or Ecash transaction
                    let isLightning = tx.paymentRequest != nil
                    
                    // Get stored token for ecash transactions
                    let storedToken = !isLightning ? self.getToken(txId: tx.id.hex) : nil
                    
                    return WalletTransaction(
                        id: tx.id.hex,
                        amount: tx.amount.value,
                        type: tx.direction == .incoming ? .incoming : .outgoing,
                        kind: isLightning ? .lightning : .ecash,
                        date: Date(timeIntervalSince1970: TimeInterval(tx.timestamp)),
                        memo: tx.memo,
                        status: .completed,
                        mintUrl: tx.mintUrl.url,
                        token: storedToken,
                        invoice: tx.paymentRequest
                    )
                }
                allTransactions.append(contentsOf: walletTxs)
            } catch {
                AppLogger.wallet.error("Failed to load transactions for mint \(mintUrlString): \(error)")
            }
        }
        
        // Add pending tokens as pending transactions
        for pendingToken in pendingTokens {
            var pendingTx = WalletTransaction(
                id: pendingToken.tokenId,
                amount: pendingToken.amount,
                type: .outgoing,
                kind: .ecash,
                date: pendingToken.date,
                memo: pendingToken.memo,
                status: .pending,
                mintUrl: pendingToken.mintUrl,
                token: pendingToken.token,
                isPendingToken: true
            )
            pendingTx.fee = pendingToken.fee
            allTransactions.append(pendingTx)
        }
        
        // Add claimed tokens as completed transactions
        for claimedToken in claimedTokens {
            var claimedTx = WalletTransaction(
                id: claimedToken.tokenId,
                amount: claimedToken.amount,
                type: .outgoing,
                kind: .ecash,
                date: claimedToken.date,
                memo: claimedToken.memo,
                status: .completed,
                mintUrl: claimedToken.mintUrl,
                token: claimedToken.token
            )
            claimedTx.fee = claimedToken.fee
            allTransactions.append(claimedTx)
        }
        
        // Sort by date descending (newest first)
        transactions = allTransactions.sorted { $0.date > $1.date }
        
        // Post notification that transactions were updated
        NotificationCenter.default.post(name: .cashuTransactionsUpdated, object: nil)
    }
    
    // MARK: - Token Persistence
    
    /// Save a token string for later retrieval
    func saveToken(txId: String, token: String) {
        var tokens = UserDefaults.standard.dictionary(forKey: StorageKeys.savedTokens) as? [String: String] ?? [:]
        tokens[txId] = token
        UserDefaults.standard.set(tokens, forKey: StorageKeys.savedTokens)
    }
    
    /// Get a stored token by transaction ID
    func getToken(txId: String) -> String? {
        let tokens = UserDefaults.standard.dictionary(forKey: StorageKeys.savedTokens) as? [String: String]
        return tokens?[txId]
    }
    
    // MARK: - Preimage Persistence

    /// Save a Lightning payment preimage (proof of payment)
    func savePreimage(quoteId: String, preimage: String) {
        var preimages = UserDefaults.standard.dictionary(forKey: "paymentPreimages") as? [String: String] ?? [:]
        preimages[quoteId] = preimage
        UserDefaults.standard.set(preimages, forKey: "paymentPreimages")
    }

    /// Get a stored preimage by quote ID
    func getPreimage(quoteId: String) -> String? {
        let preimages = UserDefaults.standard.dictionary(forKey: "paymentPreimages") as? [String: String]
        return preimages?[quoteId]
    }

    // MARK: - Pending Token Management (Outgoing)
    
    /// Save a pending token (when sending ecash)
    /// Uses index-based replacement to avoid non-atomic removeAll+append
    func savePendingToken(_ pendingToken: PendingToken) {
        if let existingIndex = pendingTokens.firstIndex(where: { $0.tokenId == pendingToken.tokenId }) {
            pendingTokens[existingIndex] = pendingToken
        } else {
            pendingTokens.append(pendingToken)
        }
        persistPendingTokens()
    }
    
    /// Load pending tokens from storage
    func loadPendingTokens() {
        if let data = UserDefaults.standard.data(forKey: StorageKeys.pendingTokens) {
            do {
                pendingTokens = try JSONDecoder().decode([PendingToken].self, from: data)
            } catch {
                AppLogger.wallet.error("Failed to load pending tokens: \(error)")
                pendingTokens = []
            }
        } else {
            pendingTokens = []
        }
    }
    
    /// Persist pending tokens to storage
    private func persistPendingTokens() {
        do {
            let data = try JSONEncoder().encode(pendingTokens)
            UserDefaults.standard.set(data, forKey: StorageKeys.pendingTokens)
        } catch {
            AppLogger.wallet.error("Failed to save pending tokens: \(error)")
        }
    }
    
    /// Remove a pending token (when claimed or confirmed spent)
    func removePendingToken(tokenId: String) {
        pendingTokens.removeAll { $0.tokenId == tokenId }
        persistPendingTokens()
    }
    
    /// Mark a token as claimed - move from pending to claimed storage
    func markTokenAsClaimed(token: String) {
        // Find the pending token by its token string
        if let pendingToken = pendingTokens.first(where: { $0.token == token }) {
            // Create a claimed token entry with fee
            let claimedToken = ClaimedToken(
                tokenId: pendingToken.tokenId,
                token: pendingToken.token,
                amount: pendingToken.amount,
                fee: pendingToken.fee,
                date: pendingToken.date,
                mintUrl: pendingToken.mintUrl,
                memo: pendingToken.memo,
                claimedDate: Date()
            )
            
            // Add to claimed tokens
            saveClaimedToken(claimedToken)
            
            // Remove from pending list
            removePendingToken(tokenId: pendingToken.tokenId)
        }
    }
    
    // MARK: - Pending Receive Token Management (Incoming)
    
    /// Save a token for later claiming
    /// Uses index-based replacement to avoid non-atomic removeAll+append
    func savePendingReceiveToken(_ token: PendingReceiveToken) {
        if let existingIndex = pendingReceiveTokens.firstIndex(where: { $0.tokenId == token.tokenId }) {
            pendingReceiveTokens[existingIndex] = token
        } else {
            pendingReceiveTokens.append(token)
        }
        persistPendingReceiveTokens()
    }
    
    /// Load pending receive tokens from storage
    func loadPendingReceiveTokens() {
        if let data = UserDefaults.standard.data(forKey: StorageKeys.pendingReceiveTokens) {
            do {
                pendingReceiveTokens = try JSONDecoder().decode([PendingReceiveToken].self, from: data)
            } catch {
                AppLogger.wallet.error("Failed to load pending receive tokens: \(error)")
                pendingReceiveTokens = []
            }
        } else {
            pendingReceiveTokens = []
        }
    }
    
    /// Persist pending receive tokens to storage
    private func persistPendingReceiveTokens() {
        do {
            let data = try JSONEncoder().encode(pendingReceiveTokens)
            UserDefaults.standard.set(data, forKey: StorageKeys.pendingReceiveTokens)
        } catch {
            AppLogger.wallet.error("Failed to save pending receive tokens: \(error)")
        }
    }
    
    /// Remove a pending receive token (after claiming)
    func removePendingReceiveToken(tokenId: String) {
        pendingReceiveTokens.removeAll { $0.tokenId == tokenId }
        persistPendingReceiveTokens()
    }
    
    // MARK: - Claimed Token Management
    
    /// Save a claimed token
    /// Uses index-based replacement to avoid non-atomic removeAll+append
    private func saveClaimedToken(_ claimedToken: ClaimedToken) {
        if let existingIndex = claimedTokens.firstIndex(where: { $0.tokenId == claimedToken.tokenId }) {
            claimedTokens[existingIndex] = claimedToken
        } else {
            claimedTokens.append(claimedToken)
        }
        persistClaimedTokens()
    }
    
    /// Load claimed tokens from storage
    func loadClaimedTokens() {
        if let data = UserDefaults.standard.data(forKey: StorageKeys.claimedTokens) {
            do {
                claimedTokens = try JSONDecoder().decode([ClaimedToken].self, from: data)
            } catch {
                AppLogger.wallet.error("Failed to load claimed tokens: \(error)")
                claimedTokens = []
            }
        } else {
            claimedTokens = []
        }
    }
    
    /// Persist claimed tokens to storage
    private func persistClaimedTokens() {
        do {
            let data = try JSONEncoder().encode(claimedTokens)
            UserDefaults.standard.set(data, forKey: StorageKeys.claimedTokens)
        } catch {
            AppLogger.wallet.error("Failed to save claimed tokens: \(error)")
        }
    }
}
