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
    private let walletDatabase: () -> WalletSqliteDatabase?
    private let getTrackedMintUrls: () -> [String]
    private let walletStore: WalletStore
    
    // MARK: - Initialization
    
    init(
        walletRepository: @escaping () -> WalletRepository?,
        walletDatabase: @escaping () -> WalletSqliteDatabase?,
        getTrackedMintUrls: @escaping () -> [String],
        walletStore: WalletStore = WalletStore()
    ) {
        self.walletRepository = walletRepository
        self.walletDatabase = walletDatabase
        self.getTrackedMintUrls = getTrackedMintUrls
        self.walletStore = walletStore
    }
    
    // MARK: - Transaction Loading
    
    /// Load transaction history from all mints
    func loadTransactions() async {
        guard let repo = walletRepository() else { return }
        
        // Load pending and claimed tokens from storage
        loadPendingTokens()
        loadPendingReceiveTokens()
        loadClaimedTokens()
        var mintQuoteTimestamps = loadMintQuoteTimestamps()
        
        // Get transactions from tracked wallets
        var allTransactions: [WalletTransaction] = []
        var completedQuoteIds: Set<String> = []
        let trackedMintUrls = Set(getTrackedMintUrls().filter { !$0.isEmpty })
        
        for mintUrlString in trackedMintUrls {
            do {
                let mintUrl = MintUrl(url: mintUrlString)
                let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
                let txs = try await wallet.listTransactions(direction: nil)
                let walletTxs: [WalletTransaction] = txs.map { tx in
                    if let quoteId = tx.quoteId {
                        completedQuoteIds.insert(quoteId)
                    }

                    let paymentMethod = tx.paymentMethod.flatMap(PaymentMethodKind.from)
                    let kind: WalletTransaction.TransactionKind

                    switch paymentMethod {
                    case .onchain:
                        kind = .onchain
                    case .bolt11, .bolt12:
                        kind = .lightning
                    case nil:
                        kind = tx.paymentRequest != nil ? .lightning : .ecash
                    }

                    let storedToken = kind == .ecash ? self.getToken(txId: tx.id.hex) : nil
                    let storedPaymentProof = tx.paymentProof
                        ?? tx.quoteId.flatMap { self.getPreimage(quoteId: $0) }

                    var walletTransaction = WalletTransaction(
                        id: tx.id.hex,
                        amount: tx.amount.value,
                        type: tx.direction == .incoming ? .incoming : .outgoing,
                        kind: kind,
                        date: Date(timeIntervalSince1970: TimeInterval(tx.timestamp)),
                        memo: tx.memo,
                        status: .completed,
                        mintUrl: tx.mintUrl.url,
                        preimage: storedPaymentProof,
                        token: storedToken,
                        invoice: tx.paymentRequest
                    )

                    walletTransaction.fee = tx.fee.value
                    return walletTransaction
                }
                allTransactions.append(contentsOf: walletTxs)
            } catch {
                AppLogger.wallet.error("Failed to load transactions for mint \(mintUrlString): \(error)")
            }
        }

        if let walletDatabase = walletDatabase() {
            do {
                let pendingMintQuotes = try await walletDatabase.getUnissuedMintQuotes()
                let pendingQuoteTransactions = await pendingTransactions(
                    from: pendingMintQuotes,
                    trackedMintUrls: trackedMintUrls,
                    completedQuoteIds: completedQuoteIds,
                    timestamps: &mintQuoteTimestamps
                )
                allTransactions.append(contentsOf: pendingQuoteTransactions)

                let meltQuotes = try await walletDatabase.getMeltQuotes()
                let meltQuoteTransactions = meltTransactions(
                    from: meltQuotes,
                    trackedMintUrls: trackedMintUrls,
                    completedQuoteIds: completedQuoteIds,
                    timestamps: &mintQuoteTimestamps
                )
                allTransactions.append(contentsOf: meltQuoteTransactions)
            } catch {
                AppLogger.wallet.error("Failed to load stored payment quotes: \(error)")
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
        
        persistMintQuoteTimestamps(for: allTransactions, using: mintQuoteTimestamps)

        // Sort by date descending (newest first)
        transactions = allTransactions.sorted { $0.date > $1.date }
        
        // Post notification that transactions were updated
        NotificationCenter.default.post(name: .cashuTransactionsUpdated, object: nil)
    }
    
    // MARK: - Token Persistence
    
    /// Save a token string for later retrieval
    func saveToken(txId: String, token: String) {
        var tokens = walletStore.loadSavedTokens()
        tokens[txId] = token
        walletStore.saveSavedTokens(tokens)
    }
    
    /// Get a stored token by transaction ID
    func getToken(txId: String) -> String? {
        walletStore.loadSavedTokens()[txId]
    }
    
    // MARK: - Preimage Persistence

    /// Save a Lightning payment preimage (proof of payment)
    func savePreimage(quoteId: String, preimage: String) {
        var preimages = walletStore.loadPaymentPreimages()
        preimages[quoteId] = preimage
        walletStore.savePaymentPreimages(preimages)
    }

    /// Get a stored preimage by quote ID
    func getPreimage(quoteId: String) -> String? {
        walletStore.loadPaymentPreimages()[quoteId]
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
        pendingTokens = walletStore.loadPendingTokens()
    }
    
    /// Persist pending tokens to storage
    private func persistPendingTokens() {
        walletStore.savePendingTokens(pendingTokens)
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
        pendingReceiveTokens = walletStore.loadPendingReceiveTokens()
    }
    
    /// Persist pending receive tokens to storage
    private func persistPendingReceiveTokens() {
        walletStore.savePendingReceiveTokens(pendingReceiveTokens)
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
        claimedTokens = walletStore.loadClaimedTokens()
    }
    
    /// Persist claimed tokens to storage
    private func persistClaimedTokens() {
        walletStore.saveClaimedTokens(claimedTokens)
    }

    private func pendingTransactions(
        from quotes: [MintQuote],
        trackedMintUrls: Set<String>,
        completedQuoteIds: Set<String>,
        timestamps: inout [String: TimeInterval]
    ) async -> [WalletTransaction] {
        var transactions: [WalletTransaction] = []

        for quote in quotes {
            guard trackedMintUrls.contains(quote.mintUrl.url) else {
                continue
            }

            let paymentMethod = PaymentMethodKind.from(quote.paymentMethod)
            guard let paymentMethod else {
                continue
            }

            // CDK's `getUnissuedMintQuotes()` always returns every BOLT12 quote
            // (`amount_issued = 0 OR payment_method = 'bolt12'`) because offers
            // are reusable. If CDK already surfaced the issued payment through
            // `wallet.listTransactions()`, skip the quote-backed fallback.
            if paymentMethod == .bolt12,
               quote.amountPaid.value > 0,
               quote.amountIssued.value >= quote.amountPaid.value,
               completedQuoteIds.contains(quote.id) {
                continue
            }

            let amount = quote.amount?.value
                ?? (quote.amountPaid.value > 0 ? quote.amountPaid.value : nil)
                ?? (quote.amountIssued.value > 0 ? quote.amountIssued.value : nil)

            guard let amount, amount > 0 else {
                continue
            }

            let timestamp = timestamps[quote.id] ?? Date().timeIntervalSince1970
            timestamps[quote.id] = timestamp
            let createdAt = Date(timeIntervalSince1970: timestamp)
            let status: WalletTransaction.TransactionStatus =
                quote.state == .issued || quote.amountIssued.value >= amount ? .completed : .pending

            var storedPaymentProof = getPreimage(quoteId: quote.id)
            var statusNote: String?

            if paymentMethod == .onchain,
               let observation = await OnchainExplorer.observePayment(
                for: quote.request,
                mintURL: quote.mintUrl.url,
                expectedAmount: amount,
                createdAfter: createdAt
               ) {
                storedPaymentProof = observation.txid
                statusNote = observation.statusText

                if getPreimage(quoteId: quote.id) != observation.txid {
                    savePreimage(quoteId: quote.id, preimage: observation.txid)
                }
            } else if paymentMethod == .onchain, storedPaymentProof != nil {
                statusNote = "Payment detected on-chain"
            }

            transactions.append(WalletTransaction(
                id: quote.id,
                amount: amount,
                type: .incoming,
                kind: paymentMethod == .onchain ? .onchain : .lightning,
                date: createdAt,
                memo: nil,
                status: status,
                statusNote: statusNote,
                mintUrl: quote.mintUrl.url,
                preimage: storedPaymentProof,
                token: nil,
                invoice: quote.request
            ))
        }

        return transactions
    }

    private func meltTransactions(
        from quotes: [MeltQuote],
        trackedMintUrls: Set<String>,
        completedQuoteIds: Set<String>,
        timestamps: inout [String: TimeInterval]
    ) -> [WalletTransaction] {
        var transactions: [WalletTransaction] = []

        for quote in quotes {
            guard let mintUrl = quote.mintUrl,
                  trackedMintUrls.contains(mintUrl.url),
                  !completedQuoteIds.contains(quote.id),
                  let paymentMethod = PaymentMethodKind.from(quote.paymentMethod) else {
                continue
            }

            let status: WalletTransaction.TransactionStatus
            switch quote.state {
            case .paid, .issued:
                status = .completed
            case .pending:
                status = .pending
            case .unpaid:
                continue
            }

            let timestamp = timestamps[quote.id] ?? Date().timeIntervalSince1970
            timestamps[quote.id] = timestamp

            var transaction = WalletTransaction(
                id: quote.id,
                amount: quote.amount.value,
                type: .outgoing,
                kind: paymentMethod == .onchain ? .onchain : .lightning,
                date: Date(timeIntervalSince1970: timestamp),
                memo: nil,
                status: status,
                mintUrl: mintUrl.url,
                preimage: quote.paymentProof ?? getPreimage(quoteId: quote.id),
                token: nil,
                invoice: quote.request
            )
            transaction.fee = quote.feeReserve.value
            transactions.append(transaction)
        }

        return transactions
    }

    private func loadMintQuoteTimestamps() -> [String: TimeInterval] {
        walletStore.loadMintQuoteTimestamps()
    }

    private func persistMintQuoteTimestamps(
        for transactions: [WalletTransaction],
        using timestamps: [String: TimeInterval]
    ) {
        let pendingQuoteIDs = Set(
            transactions
                .filter { $0.invoice != nil && ($0.kind == .lightning || $0.kind == .onchain) }
                .map(\.id)
        )

        let prunedTimestamps = timestamps.filter { pendingQuoteIDs.contains($0.key) }

        walletStore.saveMintQuoteTimestamps(prunedTimestamps)
    }
}
