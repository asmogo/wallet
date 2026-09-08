import Foundation
import Cdk

// MARK: - Transaction Service

/// Service responsible for transaction history and token persistence.
///
/// CDK 0.18 tracks the full transaction lifecycle (pending / completed /
/// failed) in its own store, including in-flight sends, melts, and mints, so
/// history is a thin projection over `wallet.listTransactions()`. The only
/// rows still synthesized app-side are unpaid/expired Lightning invoices and
/// on-chain quotes (a quote exists before any transaction does) and incoming
/// ecash held for user approval ("Receive Later" / NUT-18).
@MainActor
class TransactionService: ObservableObject {

    // MARK: - Published Properties

    /// All wallet transactions (incoming/outgoing)
    @Published var transactions: [WalletTransaction] = []

    /// Pending tokens that have been received but not yet claimed by user
    @Published var pendingReceiveTokens: [PendingReceiveToken] = []

    // MARK: - Private Properties

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
    func loadTransactions(
        includeRemoteObservations: Bool = true,
        observingQuoteID: String? = nil
    ) async {
        guard let repo = walletRepository(), let database = walletDatabase() else { return }

        loadPendingReceiveTokens()
        var mintQuoteTimestamps = loadMintQuoteTimestamps()

        // Get transactions from tracked wallets. CDK persists every send,
        // receive, mint, and melt with a stable saga-derived id and a native
        // lifecycle status, so rows map one-to-one without local merging.
        var allTransactions: [WalletTransaction] = []
        var quoteIdsWithTransactions: Set<String> = []
        let trackedMintUrls = Set(getTrackedMintUrls().filter { !$0.isEmpty }.map(MintURLIdentity.normalized))
        let previous = transactions.filter {
            !$0.isPendingReceiveToken && $0.mintUrl.map { trackedMintUrls.contains(MintURLIdentity.normalized($0)) } == true
        }
        // Synthesized invoice rows use their quote id as the row id. They must
        // not suppress fresh quote reads when a CDK account read fails.
        let previousAccountTransactions = previous.filter { $0.id != $0.quoteId }

        let accounts: [StoredWalletAccount]
        do {
            accounts = try await StoredWalletAccount.discover(database: database, repository: repo)
                .filter { trackedMintUrls.contains(MintURLIdentity.normalized($0.mintURL)) }
        } catch is CancellationError {
            return
        } catch {
            // Preserve CDK rows, but still refresh quotes and locally parked
            // tokens, whose stores may be available even when discovery fails.
            accounts = []
            allTransactions = previousAccountTransactions
            quoteIdsWithTransactions.formUnion(previousAccountTransactions.compactMap(\.quoteId))
            AppLogger.wallet.error("Unable to discover stored transaction accounts")
        }
        for account in accounts {
                let mintUrlString = account.mintURL
                let currencyUnit = account.unit
                let unitString = account.unitName
                do {
                    let txs = try await database.listTransactions(mintUrl: MintUrl(url: mintUrlString), direction: nil, unit: currencyUnit)
                    var walletTxs: [WalletTransaction] = txs.map { tx in
                        if let quoteId = tx.quoteId {
                            quoteIdsWithTransactions.insert(quoteId)
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

                        var walletTransaction = WalletTransaction(
                            id: tx.id.hex,
                            amount: tx.amount.value,
                            type: tx.direction == .incoming ? .incoming : .outgoing,
                            kind: kind,
                            date: Date(timeIntervalSince1970: TimeInterval(tx.timestamp)),
                            memo: tx.memo,
                            status: WalletTransaction.TransactionStatus(tx.status),
                            mintUrl: tx.mintUrl.url,
                            preimage: tx.paymentProof,
                            token: storedToken,
                            invoice: tx.paymentRequest
                        )

                        walletTransaction.fee = tx.fee.value
                        walletTransaction.quoteId = tx.quoteId
                        walletTransaction.sagaId = tx.sagaId
                        walletTransaction.unit = PaymentRequestDecoder.unitDescription(tx.unit)
                        return walletTransaction
                    }
                    // A sent token's string survives in the send saga until the
                    // token is claimed. Backfill rows that predate the
                    // transaction-id-keyed token store (e.g. sends recorded by
                    // an older app version) straight from the saga.
                    for index in walletTxs.indices
                        where walletTxs[index].kind == .ecash
                            && walletTxs[index].type == .outgoing
                            && walletTxs[index].status == .pending
                            && walletTxs[index].token == nil {
                        guard let sagaId = walletTxs[index].sagaId,
                              let token = await self.sendTokenFromSaga(operationId: sagaId) else { continue }
                        walletTxs[index].token = token
                        self.saveToken(txId: walletTxs[index].id, token: token)
                    }
                    allTransactions.append(contentsOf: walletTxs)
                } catch is CancellationError {
                    return
                } catch {
                    let retained = previousAccountTransactions.filter {
                        $0.unit == unitString && $0.mintUrl == mintUrlString
                    }
                    allTransactions.append(contentsOf: retained)
                    quoteIdsWithTransactions.formUnion(retained.compactMap(\.quoteId))
                    AppLogger.wallet.error(
                        "Failed to load transactions for mint \(mintUrlString), unit \(unitString): \(error)"
                    )
                }
        }

        if let walletDatabase = walletDatabase() {
            do {
                // A Lightning invoice / on-chain quote exists before CDK creates
                // any transaction for it (that happens once minting starts), so
                // unpaid and paid-not-yet-minted quotes still get synthesized
                // rows. Quotes that already have a transaction are skipped.
                let pendingMintQuotes = try await walletDatabase.getUnissuedMintQuotes()
                let pendingQuoteTransactions = await pendingTransactions(
                    from: pendingMintQuotes,
                    trackedMintUrls: trackedMintUrls,
                    quoteIdsWithTransactions: quoteIdsWithTransactions,
                    timestamps: &mintQuoteTimestamps,
                    includeRemoteObservations: includeRemoteObservations,
                    observingQuoteID: observingQuoteID
                )
                allTransactions.append(contentsOf: pendingQuoteTransactions)
            } catch is CancellationError {
                return
            } catch {
                allTransactions.append(contentsOf: previous.filter {
                    $0.id == $0.quoteId && !quoteIdsWithTransactions.contains($0.id)
                })
                AppLogger.wallet.error("Failed to load stored payment quotes: \(error)")
            }
        }

        // Unclaimed incoming ecash ("Receive Later" tokens and NUT-18 payments
        // held for approval) has no CDK counterpart until it's claimed, so each
        // entry is its own pending incoming row. Tapping the row opens the
        // claim flow (see TransactionDetailView).
        allTransactions.append(contentsOf: pendingReceiveTokens.map { pending in
            var tx = WalletTransaction(
                id: pending.tokenId,
                amount: pending.amount,
                type: .incoming,
                kind: .ecash,
                date: pending.date,
                memo: pending.memo,
                status: .pending,
                mintUrl: pending.mintUrl,
                token: pending.token
            )
            tx.statusNote = "Not claimed yet"
            tx.isPendingReceiveToken = true
            tx.cashuRequestId = pending.cashuRequestId
            tx.unit = pending.unit
            return tx
        })

        guard !Task.isCancelled else { return }
        persistMintQuoteTimestamps(for: allTransactions, using: mintQuoteTimestamps)

        // Restore from durable request metadata each load, even after payment/relaunch.
        let requests = walletStore.loadCashuRequests()
        transactions = allTransactions.map { $0.restoringDescription(from: requests) }
            .sorted { $0.date > $1.date }

        // Post notification that transactions were updated
        NotificationCenter.default.post(name: .cashuTransactionsUpdated, object: nil)
    }

    func loadCachedState() {
        loadPendingReceiveTokens()
    }

    func clearState() {
        transactions = []
        pendingReceiveTokens = []
        NotificationCenter.default.post(name: .cashuTransactionsUpdated, object: nil)
    }

    // MARK: - Token Persistence

    /// Save a token string for later retrieval (re-displaying a sent token,
    /// reclaiming it, or the receive-side receipt copy).
    func saveToken(txId: String, token: String) {
        var tokens = walletStore.loadSavedTokens()
        tokens[txId] = token
        walletStore.saveSavedTokens(tokens)
    }

    /// Get a stored token by transaction ID
    func getToken(txId: String) -> String? {
        walletStore.loadSavedTokens()[txId]
    }

    /// Look up the transaction id under which a token string was stored.
    func transactionId(forToken token: String) -> String? {
        walletStore.loadSavedTokens().first(where: { $0.value == token })?.key
    }

    /// Extract the encoded token from a send saga's persisted JSON
    /// (`data.kind == "send"` sagas carry the token until claim).
    private func sendTokenFromSaga(operationId: String) async -> String? {
        guard let sagaJSON = try? await walletDatabase()?.getSaga(id: operationId),
              let data = sagaJSON.data(using: .utf8),
              let saga = try? JSONDecoder().decode(SagaTokenPayload.self, from: data),
              saga.data.kind == "send" else {
            return nil
        }
        return saga.data.data.token
    }

    private struct SagaTokenPayload: Decodable {
        struct OperationData: Decodable {
            struct Body: Decodable { let token: String? }
            let kind: String
            let data: Body
        }
        let data: OperationData
    }

    // MARK: - Preimage Persistence (on-chain observations)

    /// Save a Lightning payment preimage or on-chain txid (proof of payment).
    /// Lightning preimages come from CDK transactions directly; this store now
    /// only carries on-chain explorer observations for quotes without a CDK
    /// transaction yet.
    func savePreimage(quoteId: String, preimage: String) {
        var preimages = walletStore.loadPaymentPreimages()
        preimages[quoteId] = preimage
        walletStore.savePaymentPreimages(preimages)
    }

    /// Get a stored preimage by quote ID
    func getPreimage(quoteId: String) -> String? {
        walletStore.loadPaymentPreimages()[quoteId]
    }

    // MARK: - Pending Receive Token Management (Incoming)

    /// Save a token for later claiming.
    /// Uses index-based replacement to avoid non-atomic removeAll+append, and
    /// de-duplicates by token string so parking the same ecash repeatedly
    /// doesn't create redundant History rows.
    func savePendingReceiveToken(_ token: PendingReceiveToken) {
        if let existingIndex = pendingReceiveTokens.firstIndex(where: { $0.tokenId == token.tokenId }) {
            pendingReceiveTokens[existingIndex] = token
        } else if let existingIndex = pendingReceiveTokens.firstIndex(where: { $0.token == token.token }) {
            let existing = pendingReceiveTokens[existingIndex]
            pendingReceiveTokens[existingIndex] = PendingReceiveToken(
                tokenId: existing.tokenId,
                token: token.token,
                amount: token.amount,
                unit: token.unit,
                date: existing.date,
                mintUrl: token.mintUrl,
                cashuRequestId: existing.cashuRequestId ?? token.cashuRequestId,
                memo: token.memo ?? existing.memo
            )
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

    private func pendingTransactions(
        from quotes: [MintQuote],
        trackedMintUrls: Set<String>,
        quoteIdsWithTransactions: Set<String>,
        timestamps: inout [String: TimeInterval],
        includeRemoteObservations: Bool,
        observingQuoteID: String?
    ) async -> [WalletTransaction] {
        var transactions: [WalletTransaction] = []

        for quote in quotes {
            guard trackedMintUrls.contains(MintURLIdentity.normalized(quote.mintUrl.url)) else {
                continue
            }

            let paymentMethod = PaymentMethodKind.from(quote.paymentMethod)
            guard let paymentMethod else {
                continue
            }

            // Once CDK has a transaction for this quote — pending while a mint
            // is in flight, completed afterwards — the CDK row is authoritative
            // and the quote-backed row would only duplicate it. (BOLT12 offers
            // always stay in `getUnissuedMintQuotes()` because the SQL filter is
            // `amount_issued = 0 OR payment_method = 'bolt12'`.)
            if quoteIdsWithTransactions.contains(quote.id) {
                continue
            }

            // BOLT12 offers are reusable and long-lived, so a created-but-unpaid
            // offer must stay out of history entirely. Surface a BOLT12 quote
            // only once a payment has actually arrived (amountPaid/amountIssued),
            // ignoring the offer's nominal amount. Other methods keep showing
            // their pending quote (e.g. an unpaid BOLT11 invoice you generated).
            let amount: UInt64?
            if paymentMethod == .bolt12 {
                amount = quote.amountPaid.value > 0
                    ? quote.amountPaid.value
                    : (quote.amountIssued.value > 0 ? quote.amountIssued.value : nil)
            } else {
                amount = quote.amount?.value
                    ?? (quote.amountPaid.value > 0 ? quote.amountPaid.value : nil)
                    ?? (quote.amountIssued.value > 0 ? quote.amountIssued.value : nil)
            }

            guard let amount, amount > 0 else {
                continue
            }

            // CDK 0.18 quotes carry `updatedAt` (creation time for an untouched
            // quote). The local first-seen map only backfills legacy rows that
            // predate the column.
            let timestamp: TimeInterval
            if quote.updatedAt > 0 {
                timestamp = TimeInterval(quote.updatedAt)
            } else {
                let firstSeen = timestamps[quote.id] ?? Date().timeIntervalSince1970
                timestamps[quote.id] = firstSeen
                timestamp = firstSeen
            }
            let createdAt = Date(timeIntervalSince1970: timestamp)
            // A paid-but-unissued quote stays Pending even past expiry: the
            // invoice settled, and NUT-04 lets the wallet mint it afterwards.
            let isPaid = quote.state == .paid || quote.state == .issued || quote.amountPaid.value > 0
            let isUnpaidBolt11 = paymentMethod == .bolt11 && !isPaid
            let isExpiredUnpaidInvoice = isUnpaidBolt11
                && quote.expiry > 0
                && Date().timeIntervalSince1970 > Double(quote.expiry)
            let status: WalletTransaction.TransactionStatus =
                quote.state == .issued || quote.amountIssued.value >= amount ? .completed
                : isExpiredUnpaidInvoice ? .expired
                : .pending

            var storedPaymentProof = getPreimage(quoteId: quote.id)
            var statusNote: String?

            if includeRemoteObservations,
               observingQuoteID == nil || observingQuoteID == quote.id,
               paymentMethod == .onchain,
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

            var transaction = WalletTransaction(
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
                invoice: quote.request,
                quoteId: quote.id
            )
            transaction.unit = PaymentRequestDecoder.unitDescription(quote.unit)
            transaction.isUnpaidInvoice = isUnpaidBolt11
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

extension WalletTransaction.TransactionStatus {
    /// Project CDK's native transaction lifecycle onto the app's row status.
    /// `.expired` has no CDK counterpart; it is synthesized for unpaid invoices
    /// past their expiry.
    init(_ status: Cdk.TransactionStatus) {
        switch status {
        case .pending: self = .pending
        case .completed: self = .completed
        case .failed: self = .failed
        }
    }
}
