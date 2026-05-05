import CryptoKit
import Foundation
import CashuDevKit

// MARK: - Lightning Service

/// Service responsible for Lightning Network operations (NUT-04/NUT-05).
/// Handles minting (receiving via Lightning) and melting (paying via Lightning).
@MainActor
class LightningService: ObservableObject {
    private enum StorageKeys {
        static let trackedOnchainMeltMintURLs = "trackedOnchainMeltMintURLs"
    }

    private enum QuoteExpiry {
        static let never: UInt64 = 0
        static let localNeverExpiresSentinel: UInt64 = 253_402_300_799
    }

    private struct RecoveredOnchainMeltResult {
        let preimage: String?
        let feePaid: UInt64
    }

    private actor OnchainMeltCompletionCoordinator {
        private var continuation: CheckedContinuation<FinalizedMelt, Error>?
        private var result: Result<FinalizedMelt, Error>?

        func wait() async throws -> FinalizedMelt {
            if let result {
                return try result.get()
            }

            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func succeed(_ finalizedMelt: FinalizedMelt) {
            guard result == nil else { return }
            result = .success(finalizedMelt)

            if let continuation {
                self.continuation = nil
                continuation.resume(returning: finalizedMelt)
            }
        }

        func fail(_ error: Error) {
            guard result == nil else { return }
            result = .failure(error)

            if let continuation {
                self.continuation = nil
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Published Properties
    
    /// Whether an operation is in progress
    @Published var isLoading = false
    
    // MARK: - Dependencies
    
    private let walletRepository: () -> WalletRepository?
    private let walletDatabase: () -> WalletSqliteDatabase?
    private let getActiveMint: () -> MintInfo?
    private let onWalletStateUpdated: () async -> Void
    private var lastOnchainMeltRecoveryAt: Date?
    private var onchainMeltCleanupInFlight: Set<String> = []
    private var mintQuotesInFlight: Set<String> = []
    
    // MARK: - Initialization
    
    init(
        walletRepository: @escaping () -> WalletRepository?,
        walletDatabase: @escaping () -> WalletSqliteDatabase?,
        getActiveMint: @escaping () -> MintInfo?,
        onWalletStateUpdated: @escaping () async -> Void = {}
    ) {
        self.walletRepository = walletRepository
        self.walletDatabase = walletDatabase
        self.getActiveMint = getActiveMint
        self.onWalletStateUpdated = onWalletStateUpdated
    }
    
    // MARK: - Minting (NUT-04) - Receive via Lightning
    
    /// Create a mint quote for the requested payment method.
    /// - Parameters:
    ///   - amount: Amount in satoshis when required by the payment method
    ///   - method: The payment method to use for the quote
    /// - Returns: Mint quote with request details
    func createMintQuote(
        amount: UInt64?,
        method: PaymentMethodKind = .bolt11
    ) async throws -> MintQuoteInfo {
        guard let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }
        
        isLoading = true
        defer { isLoading = false }

        if method.requiresMintAmount {
            guard let amount, amount > 0 else {
                throw WalletError.networkError("An amount is required for \(method.displayName) receive requests.")
            }
        }

        if method == .onchain {
            guard let amount else {
                throw WalletError.notInitialized
            }
            return try await createOnchainMintQuote(
                amount: amount,
                activeMint: activeMint
            )
        }

        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)

        let quote = try await wallet.mintQuote(
            paymentMethod: method.cdkMethod,
            amount: amount.map { Amount(value: $0) },
            description: nil,
            extra: nil
        )

        await persistMintQuote(quote, paymentMethod: method)

        return mintQuoteInfo(from: quote, fallbackAmount: amount, paymentMethod: method)
    }

    func checkMintQuote(quoteId: String) async throws -> MintQuoteInfo {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let activeMintURL = getActiveMint()?.url ?? "<none>"

        if let walletDatabase = walletDatabase(),
           let existingQuote = try await walletDatabase.getMintQuote(quoteId: quoteId) {
            let storedPaymentMethod = PaymentMethodKind.from(existingQuote.paymentMethod)
            AppLogger.wallet.info(
                "Checking mint quote \(quoteId, privacy: .public) using stored mint \(existingQuote.mintUrl.url, privacy: .public) (active mint: \(activeMintURL, privacy: .public), method: \(storedPaymentMethod?.rawValue ?? "unknown", privacy: .public))"
            )

            if storedPaymentMethod == .onchain {
                let storedQuote = try await refreshStoredOnchainMintQuoteStatus(
                    existingQuote,
                    fallbackAmount: existingQuote.amount?.value
                )
                return mintQuoteInfo(
                    from: storedQuote,
                    fallbackAmount: existingQuote.amount?.value,
                    paymentMethod: .onchain
                )
            }

            if storedPaymentMethod == .bolt12 {
                await persistMintQuoteIfNeeded(existingQuote, paymentMethod: .bolt12)
            }

            let wallet = try await repo.getWallet(mintUrl: existingQuote.mintUrl, unit: .sat)
            let quote = try await wallet.checkMintQuote(quoteId: quoteId)
            let paymentMethod = PaymentMethodKind.from(quote.paymentMethod) ?? storedPaymentMethod ?? .bolt11
            await persistMintQuote(
                quote,
                paymentMethod: paymentMethod,
                fallbackAmount: existingQuote.amount?.value
            )
            return mintQuoteInfo(
                from: quote,
                fallbackAmount: existingQuote.amount?.value,
                paymentMethod: paymentMethod
            )
        }

        guard let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }

        AppLogger.wallet.info(
            "Checking mint quote \(quoteId, privacy: .public) using active mint \(activeMint.url, privacy: .public) because no stored quote was found"
        )

        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let quote = try await wallet.checkMintQuote(quoteId: quoteId)
        let paymentMethod = PaymentMethodKind.from(quote.paymentMethod) ?? .bolt11
        await persistMintQuote(quote, paymentMethod: paymentMethod)
        return mintQuoteInfo(from: quote, fallbackAmount: nil, paymentMethod: paymentMethod)
    }
    
    /// Mint tokens after invoice is paid
    /// - Parameter quoteId: The quote ID to mint
    /// - Returns: Total amount minted
    func mintTokens(quoteId: String) async throws -> UInt64 {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        guard !mintQuotesInFlight.contains(quoteId) else {
            throw WalletError.networkError("Mint quote is already being minted.")
        }

        mintQuotesInFlight.insert(quoteId)
        defer {
            mintQuotesInFlight.remove(quoteId)
        }
        
        isLoading = true
        defer { isLoading = false }

        let activeMintURL = getActiveMint()?.url ?? "<none>"
        let mintUrl: MintUrl
        let amountSplitTarget: SplitTarget

        if let walletDatabase = walletDatabase(),
           let existingQuote = try await walletDatabase.getMintQuote(quoteId: quoteId) {
            let storedPaymentMethod = PaymentMethodKind.from(existingQuote.paymentMethod)
            let currentQuote = if storedPaymentMethod == .onchain {
                try await refreshStoredOnchainMintQuoteStatus(
                    existingQuote,
                    fallbackAmount: existingQuote.amount?.value
                )
            } else {
                existingQuote
            }

            let normalizedQuote = mintQuoteForLocalStorage(
                currentQuote,
                paymentMethod: storedPaymentMethod ?? .bolt11,
                fallbackAmount: nil
            )
            if normalizedQuote.amount?.value != currentQuote.amount?.value
                || normalizedQuote.expiry != currentQuote.expiry {
                try await replaceStoredMintQuote(normalizedQuote, in: walletDatabase)
            }

            mintUrl = normalizedQuote.mintUrl
            amountSplitTarget = mintAmountSplitTarget(for: normalizedQuote)

            if storedPaymentMethod == .onchain,
               normalizedQuote.amountPaid.value <= normalizedQuote.amountIssued.value {
                throw WalletError.networkError(
                    "Mint has not credited this on-chain quote yet (amount_paid=\(normalizedQuote.amountPaid.value), amount_issued=\(normalizedQuote.amountIssued.value))."
                )
            }

            if storedPaymentMethod == .bolt12 {
                await persistMintQuoteIfNeeded(normalizedQuote, paymentMethod: .bolt12)
            }
            if let operationId = normalizedQuote.usedByOperation {
                AppLogger.wallet.info(
                    "Releasing stored mint quote reservation \(operationId, privacy: .public) before retrying quote \(quoteId, privacy: .public)"
                )
                do {
                    try await walletDatabase.releaseMintQuote(operationId: operationId)
                    try? await walletDatabase.deleteSaga(id: operationId)
                    if let refreshedQuote = try await walletDatabase.getMintQuote(quoteId: quoteId),
                       refreshedQuote.usedByOperation != nil {
                        AppLogger.wallet.info(
                            "Mint quote \(quoteId, privacy: .public) is still marked reserved after release; clearing local reservation"
                        )
                        try await replaceStoredMintQuote(
                            mintQuoteClearingReservation(refreshedQuote),
                            in: walletDatabase
                        )
                    }
                } catch {
                    AppLogger.wallet.error(
                        "Failed to release stored mint quote reservation \(operationId, privacy: .public): \(String(describing: error), privacy: .public)"
                    )
                }
            }
            AppLogger.wallet.info(
                "Minting quote \(quoteId, privacy: .public) using stored mint \(mintUrl.url, privacy: .public) (active mint: \(activeMintURL, privacy: .public))"
            )
        } else if let activeMint = getActiveMint() {
            mintUrl = MintUrl(url: activeMint.url)
            amountSplitTarget = .none
            AppLogger.wallet.info(
                "Minting quote \(quoteId, privacy: .public) using active mint \(activeMint.url, privacy: .public) because no stored quote was found"
            )
        } else {
            throw WalletError.notInitialized
        }

        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let waitLoggerTask = Task { [weak self, quoteId] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.logStoredMintDiagnostics(
                quoteId: quoteId,
                prefix: "Still waiting for mint"
            )
            AppLogger.wallet.info(
                "Still waiting for mint for quote \(quoteId, privacy: .public)"
            )
        }

        defer {
            waitLoggerTask.cancel()
        }

        let proofs = try await wallet.mintUnified(
            quoteId: quoteId,
            amountSplitTarget: amountSplitTarget,
            spendingConditions: nil
        )
        
        return proofs.reduce(UInt64(0)) { $0 + $1.amount.value }
    }
    
    // MARK: - Melting (NUT-05) - Pay via Lightning
    
    /// Create a melt quote for paying a Lightning payment request
    /// - Parameter request: The BOLT11 invoice or BOLT12 offer to pay
    /// - Returns: Melt quote with fee information
    func createMeltQuote(request: String) async throws -> MeltQuoteInfo {
        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)

        if PaymentRequestParser.isBitcoinAddress(request) {
            throw WalletError.networkError("On-chain payments require an amount before requesting a quote.")
        }

        let parsedRequest = try LightningRequestParser.parse(request)
        let paymentMethod = PaymentMethodKind.from(parsedRequest.method) ?? .bolt11
        
        let quote = try await wallet.meltQuote(
            method: parsedRequest.method,
            request: parsedRequest.request,
            options: nil,
            extra: nil
        )

        return meltQuoteInfo(from: quote, paymentMethod: paymentMethod)
    }
    
    /// Backward-compatible wrapper for older bolt11-specific call sites.
    func createMeltQuote(invoice: String) async throws -> MeltQuoteInfo {
        try await createMeltQuote(request: invoice)
    }
    
    /// Create a melt quote for paying a human-readable address (BIP 353 / Lightning Address)
    /// - Parameters:
    ///   - address: The user@domain address
    ///   - amount: Amount in satoshis
    /// - Returns: Melt quote with fee information
    func createHumanReadableMeltQuote(address: String, amount: UInt64) async throws -> MeltQuoteInfo {
        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)

        let amountMsat = Amount(value: amount * 1000)
        let quote = try await wallet.meltHumanReadable(
            address: address,
            amountMsat: amountMsat,
            network: bitcoinNetwork(for: activeMint.url)
        )

        return meltQuoteInfo(from: quote, paymentMethod: .bolt11)
    }

    func createOnchainMeltQuote(address: String, amount: UInt64) async throws -> MeltQuoteInfo {
        guard let activeMint = getActiveMint(),
              let walletDatabase = walletDatabase() else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        let normalizedAddress = PaymentRequestParser.normalizeBitcoinRequest(address)
        let response: [OnchainMeltQuoteResponse] = try await performOnchainRequest(
            url: try onchainMeltQuoteURL(for: activeMint.url),
            method: "POST",
            body: try JSONEncoder().encode(
                OnchainMeltQuoteRequestBody(
                    request: normalizedAddress,
                    amount: amount
                )
            ),
            logContext: "On-chain melt quote create"
        )

        guard let quoteResponse = response.first else {
            throw WalletError.networkError("Mint returned no on-chain melt quote.")
        }

        let storedQuote = makeStoredOnchainMeltQuote(
            response: quoteResponse,
            mintURLString: activeMint.url,
            version: 0
        )
        try await walletDatabase.addMeltQuote(quote: storedQuote)
        trackOnchainMeltQuote(quoteId: storedQuote.id, mintURLString: activeMint.url)

        return meltQuoteInfo(from: storedQuote, paymentMethod: .onchain)
    }

    func subscribeToMintQuote(
        quoteId: String,
        paymentMethod: PaymentMethodKind
    ) async throws -> ActiveSubscription? {
        guard let subscriptionKind = paymentMethod.subscriptionKind else {
            return nil
        }

        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }

        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let params = SubscribeParams(kind: subscriptionKind, filters: [quoteId], id: nil)
        return try await wallet.subscribe(params: params)
    }
    
    /// Pay a Lightning invoice (melt tokens)
    /// - Parameter quoteId: The quote ID to melt
    /// - Returns: Payment preimage if successful
    func meltTokens(quoteId: String) async throws -> String? {
        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }
        
        isLoading = true
        defer { isLoading = false }

        let storedMeltQuote = try await walletDatabase()?.getMeltQuote(quoteId: quoteId)
        let isOnchainMelt = storedMeltQuote.flatMap { PaymentMethodKind.from($0.paymentMethod) } == .onchain
        let mintURLString = isOnchainMelt
            ? trackedOnchainMeltQuoteMintURLs()[quoteId] ?? activeMint.url
            : activeMint.url
        let mintUrl = MintUrl(url: mintURLString)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)

        if isOnchainMelt {
            trackOnchainMeltQuote(quoteId: quoteId, mintURLString: mintURLString)
            if mintURLString != activeMint.url {
                AppLogger.wallet.info(
                    "Preparing on-chain melt quote \(quoteId, privacy: .public) using tracked mint \(mintURLString, privacy: .public) (active mint: \(activeMint.url, privacy: .public))"
                )
            }
        }

        let waitLoggerTask = Task { [weak self, quoteId] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.logStoredMeltDiagnostics(
                quoteId: quoteId,
                prefix: "Still waiting for melt confirmation"
            )
            AppLogger.wallet.info(
                "Still waiting for melt confirmation for quote \(quoteId, privacy: .public)"
            )
        }

        defer {
            waitLoggerTask.cancel()
        }

        AppLogger.wallet.info(
            "Preparing melt confirmation for quote \(quoteId, privacy: .public) on mint \(mintUrl.url, privacy: .public) (payment method: \(isOnchainMelt ? "onchain" : "lightning", privacy: .public))"
        )
        let preparedMelt = try await wallet.prepareMelt(quoteId: quoteId)
        AppLogger.wallet.info(
            "Prepared melt quote \(quoteId, privacy: .public); awaiting confirm()"
        )
        let result: FinalizedMelt
        if isOnchainMelt, let walletDatabase = walletDatabase() {
            let completionCoordinator = OnchainMeltCompletionCoordinator()

            let confirmTask = Task { [quoteId] in
                do {
                    let confirmed = try await preparedMelt.confirm()
                    await completionCoordinator.succeed(confirmed)
                } catch is CancellationError {
                    AppLogger.wallet.info(
                        "On-chain melt quote \(quoteId, privacy: .public) confirm task was cancelled after local recovery took over"
                    )
                } catch {
                    AppLogger.wallet.error(
                        "On-chain melt quote \(quoteId, privacy: .public) confirm task failed before local fallback completed: \(String(describing: error), privacy: .public)"
                    )
                }
            }

            let statusPollTask = Task { [weak self, quoteId, mintURLString] in
                guard let self else { return }

                var attempt = 0
                while !Task.isCancelled {
                    attempt += 1
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { return }

                    do {
                        let status: OnchainMeltQuoteResponse = try await self.performOnchainRequest(
                            url: try self.onchainMeltQuoteURL(for: mintURLString, quoteId: quoteId),
                            method: "GET",
                            logContext: "On-chain melt quote status \(quoteId) poll \(attempt)"
                        )

                        AppLogger.wallet.info(
                            "On-chain melt quote \(quoteId, privacy: .public) poll \(attempt, privacy: .public) summary: state=\(status.state.rawValue, privacy: .public), payment_proof_present=\(status.paymentProof != nil, privacy: .public), change_count=\(status.change?.count ?? 0, privacy: .public)"
                        )

                        if status.state == .paid || status.state == .issued {
                            await self.logStoredMeltDiagnostics(
                                quoteId: quoteId,
                                prefix: "On-chain melt quote reached \(status.state.rawValue)"
                            )
                            AppLogger.wallet.info(
                                "On-chain melt quote \(quoteId, privacy: .public) is already \(status.state.rawValue, privacy: .public) on the mint; applying local recovery fallback"
                            )

                            confirmTask.cancel()

                            let recovered = try await self.recoverPaidOnchainMelt(
                                quoteId: quoteId,
                                mintURLString: mintURLString,
                                status: status,
                                wallet: wallet,
                                walletDatabase: walletDatabase
                            )
                            await completionCoordinator.succeed(
                                FinalizedMelt(
                                    quoteId: quoteId,
                                    state: .paid,
                                    preimage: recovered.preimage,
                                    change: nil,
                                    amount: Amount(value: status.amount),
                                    feePaid: Amount(value: recovered.feePaid)
                                )
                            )
                            return
                        }
                    } catch {
                        AppLogger.wallet.error(
                            "Failed to poll on-chain melt quote \(quoteId, privacy: .public): \(String(describing: error), privacy: .public)"
                        )
                    }
                }
            }

            defer {
                confirmTask.cancel()
                statusPollTask.cancel()
            }

            result = try await completionCoordinator.wait()
            clearTrackedOnchainMeltQuote(quoteId: quoteId)
        } else {
            result = try await preparedMelt.confirm()
        }

        AppLogger.wallet.info(
            "Melt confirm returned for quote \(quoteId, privacy: .public): state=\(self.quoteStateLabel(result.state), privacy: .public), preimage_present=\(result.preimage != nil, privacy: .public), change_count=\(result.change?.count ?? 0, privacy: .public), fee_paid=\(result.feePaid.value, privacy: .public)"
        )
        return result.preimage
    }

    private func mintQuoteInfo(
        from quote: MintQuote,
        fallbackAmount: UInt64?,
        paymentMethod: PaymentMethodKind
    ) -> MintQuoteInfo {
        let resolvedAmount = quote.amount?.value
            ?? (quote.amountPaid.value > 0 ? quote.amountPaid.value : nil)
            ?? fallbackAmount

        return MintQuoteInfo(
            id: quote.id,
            request: quote.request,
            amount: resolvedAmount,
            paymentMethod: paymentMethod,
            state: mintQuoteState(from: quote),
            expiry: displayExpiry(quote.expiry)
        )
    }

    private func mintQuoteState(from quote: MintQuote) -> MintQuoteState {
        if quote.amountPaid.value > 0, quote.amountIssued.value >= quote.amountPaid.value {
            return .issued
        }

        if quote.amountPaid.value > quote.amountIssued.value {
            return .paid
        }

        return MintQuoteState(quote.state)
    }

    private func meltQuoteInfo(
        from quote: MeltQuote,
        paymentMethod: PaymentMethodKind
    ) -> MeltQuoteInfo {
        MeltQuoteInfo(
            id: quote.id,
            amount: quote.amount.value,
            feeReserve: quote.feeReserve.value,
            paymentMethod: paymentMethod,
            state: MeltQuoteState(quote.state),
            expiry: displayExpiry(quote.expiry)
        )
    }

    private func displayExpiry(_ expiry: UInt64) -> UInt64? {
        guard expiry != QuoteExpiry.never,
              expiry != QuoteExpiry.localNeverExpiresSentinel else {
            return nil
        }

        return expiry
    }

    private func persistMintQuoteIfNeeded(
        _ quote: MintQuote,
        paymentMethod: PaymentMethodKind
    ) async {
        let normalizedQuote = mintQuoteForLocalStorage(quote, paymentMethod: paymentMethod)
        guard normalizedQuote.expiry != quote.expiry else { return }

        await persistMintQuote(normalizedQuote)
    }

    private func persistMintQuote(
        _ quote: MintQuote,
        paymentMethod: PaymentMethodKind,
        fallbackAmount: UInt64? = nil
    ) async {
        await persistMintQuote(
            mintQuoteForLocalStorage(
                quote,
                paymentMethod: paymentMethod,
                fallbackAmount: fallbackAmount
            )
        )
    }

    private func persistMintQuote(_ quote: MintQuote) async {
        do {
            guard let walletDatabase = walletDatabase() else { return }
            let quoteToPersist = await mintQuoteClearingOrphanedReservationIfNeeded(
                quote,
                in: walletDatabase
            )
            try await replaceStoredMintQuote(quoteToPersist, in: walletDatabase)
        } catch {
            AppLogger.wallet.error(
                "Failed to persist mint quote \(quote.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func mintQuoteForLocalStorage(
        _ quote: MintQuote,
        paymentMethod: PaymentMethodKind,
        fallbackAmount: UInt64? = nil
    ) -> MintQuote {
        let expiry = paymentMethod == .bolt12 && quote.expiry == QuoteExpiry.never
            ? QuoteExpiry.localNeverExpiresSentinel
            : quote.expiry

        let amount = normalizedMintQuoteAmount(
            for: quote,
            paymentMethod: paymentMethod,
            fallbackAmount: fallbackAmount
        )

        guard expiry != quote.expiry || amount?.value != quote.amount?.value else {
            return quote
        }

        return MintQuote(
            id: quote.id,
            amount: amount,
            unit: quote.unit,
            request: quote.request,
            state: quote.state,
            expiry: expiry,
            mintUrl: quote.mintUrl,
            amountIssued: quote.amountIssued,
            amountPaid: quote.amountPaid,
            paymentMethod: quote.paymentMethod,
            secretKey: quote.secretKey,
            usedByOperation: quote.usedByOperation,
            version: quote.version
        )
    }

    private func normalizedMintQuoteAmount(
        for quote: MintQuote,
        paymentMethod: PaymentMethodKind,
        fallbackAmount: UInt64?
    ) -> Amount? {
        guard paymentMethod == .onchain, quote.amount == nil else {
            return quote.amount
        }

        if quote.amountPaid.value > 0 {
            return Amount(value: quote.amountPaid.value)
        }

        if quote.amountIssued.value > 0 {
            return Amount(value: quote.amountIssued.value)
        }

        if let fallbackAmount, fallbackAmount > 0 {
            return Amount(value: fallbackAmount)
        }

        return nil
    }

    private func mintAmountSplitTarget(for quote: MintQuote) -> SplitTarget {
        guard PaymentMethodKind.from(quote.paymentMethod) == .onchain else {
            return .none
        }

        if let amount = quote.amount?.value, amount > 0 {
            return .value(amount: Amount(value: amount))
        }

        if quote.amountPaid.value > 0 {
            return .value(amount: Amount(value: quote.amountPaid.value))
        }

        if quote.amountIssued.value > 0 {
            return .value(amount: Amount(value: quote.amountIssued.value))
        }

        return .none
    }

    private func mintQuoteClearingOrphanedReservationIfNeeded(
        _ quote: MintQuote,
        in walletDatabase: WalletSqliteDatabase
    ) async -> MintQuote {
        guard let operationId = quote.usedByOperation else {
            return quote
        }

        do {
            guard try await walletDatabase.getSaga(id: operationId) == nil else {
                return quote
            }

            AppLogger.wallet.info(
                "Clearing orphaned mint quote reservation \(operationId, privacy: .public) for quote \(quote.id, privacy: .public)"
            )
            return mintQuoteClearingReservation(quote)
        } catch {
            AppLogger.wallet.error(
                "Failed to inspect mint quote reservation \(operationId, privacy: .public) for quote \(quote.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return quote
        }
    }

    private func mintQuoteClearingReservation(_ quote: MintQuote) -> MintQuote {
        MintQuote(
            id: quote.id,
            amount: quote.amount,
            unit: quote.unit,
            request: quote.request,
            state: quote.state,
            expiry: quote.expiry,
            mintUrl: quote.mintUrl,
            amountIssued: quote.amountIssued,
            amountPaid: quote.amountPaid,
            paymentMethod: quote.paymentMethod,
            secretKey: quote.secretKey,
            usedByOperation: nil,
            version: quote.version
        )
    }

    private func replaceStoredMintQuote(
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

    private func refreshStoredOnchainMintQuoteStatus(
        _ existingQuote: MintQuote,
        fallbackAmount: UInt64?
    ) async throws -> MintQuote {
        let status: OnchainMintQuoteResponse = try await performOnchainRequest(
            url: try onchainMintQuoteURL(
                for: existingQuote.mintUrl.url,
                quoteId: existingQuote.id
            ),
            method: "GET",
            logContext: "On-chain mint quote status \(existingQuote.id)"
        )

        let refreshedQuote = makeStoredOnchainMintQuote(
            response: status,
            existingQuote: existingQuote,
            fallbackAmount: fallbackAmount
        )

        guard let walletDatabase = walletDatabase() else {
            return refreshedQuote
        }

        let quoteToPersist = await mintQuoteClearingOrphanedReservationIfNeeded(
            refreshedQuote,
            in: walletDatabase
        )
        try await replaceStoredMintQuote(quoteToPersist, in: walletDatabase)
        return quoteToPersist
    }

    private func makeStoredOnchainMintQuote(
        response: OnchainMintQuoteResponse,
        existingQuote: MintQuote,
        fallbackAmount: UInt64?
    ) -> MintQuote {
        let amountValue = response.amount
            ?? existingQuote.amount?.value
            ?? (response.amountPaid > 0 ? response.amountPaid : nil)
            ?? fallbackAmount

        return MintQuote(
            id: response.quote,
            amount: amountValue.map { Amount(value: $0) },
            unit: currencyUnit(from: response.unit) ?? existingQuote.unit,
            request: response.request,
            state: response.quoteState(existingState: existingQuote.state),
            expiry: response.expiry ?? existingQuote.expiry,
            mintUrl: existingQuote.mintUrl,
            amountIssued: Amount(value: response.amountIssued),
            amountPaid: Amount(value: response.amountPaid),
            paymentMethod: PaymentMethodKind.onchain.cdkMethod,
            secretKey: existingQuote.secretKey,
            usedByOperation: existingQuote.usedByOperation,
            version: existingQuote.version
        )
    }

    private func createOnchainMintQuote(
        amount: UInt64,
        activeMint: MintInfo
    ) async throws -> MintQuoteInfo {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)

        let quote = try await wallet.mintQuote(
            paymentMethod: PaymentMethodKind.onchain.cdkMethod,
            amount: Amount(value: amount),
            description: nil,
            extra: "{}"
        )

        await persistMintQuote(quote, paymentMethod: .onchain, fallbackAmount: amount)

        return mintQuoteInfo(from: quote, fallbackAmount: amount, paymentMethod: .onchain)
    }

    private func performOnchainRequest<Response: Decodable>(
        url: URL,
        method: String,
        body: Data? = nil,
        logContext: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        if let logContext {
            AppLogger.wallet.info(
                "\(logContext, privacy: .public) request: \(method, privacy: .public) \(url.absoluteString, privacy: .public)"
            )
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalletError.networkError("Mint returned a non-HTTP response.")
        }

        let responseBody = formattedOnchainResponseBody(from: data)

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let logContext {
                if httpResponse.statusCode == 404 {
                    AppLogger.wallet.info(
                        "\(logContext, privacy: .public) failed with status \(httpResponse.statusCode, privacy: .public): \(responseBody, privacy: .public)"
                    )
                } else {
                    AppLogger.wallet.error(
                        "\(logContext, privacy: .public) failed with status \(httpResponse.statusCode, privacy: .public): \(responseBody, privacy: .public)"
                    )
                }
            }
            let apiError = try? JSONDecoder().decode(OnchainMintErrorResponse.self, from: data)
            let detail = apiError?.detail ?? responseBody
            throw WalletError.networkError(detail)
        }

        if let logContext {
            AppLogger.wallet.info(
                "\(logContext, privacy: .public) returned status \(httpResponse.statusCode, privacy: .public): \(responseBody, privacy: .public)"
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            if let logContext {
                AppLogger.wallet.error(
                    "\(logContext, privacy: .public) failed to decode: \(responseBody, privacy: .public)"
                )
            }
            throw WalletError.networkError("Failed to decode on-chain mint quote response: \(responseBody)")
        }
    }

    private func formattedOnchainResponseBody(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }

        return String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
    }

    func recoverPendingOnchainMeltQuotes(force: Bool = false) async {
        guard let repo = walletRepository(),
              let walletDatabase = walletDatabase() else {
            return
        }

        if !force,
           let lastOnchainMeltRecoveryAt,
           Date().timeIntervalSince(lastOnchainMeltRecoveryAt) < 10 {
            return
        }
        lastOnchainMeltRecoveryAt = Date()

        let trackedQuotes = trackedOnchainMeltQuoteMintURLs()
        guard !trackedQuotes.isEmpty else { return }

        for (quoteId, mintURLString) in trackedQuotes {
            do {
                guard !onchainMeltCleanupInFlight.contains(quoteId) else {
                    continue
                }

                guard let storedQuote = try await walletDatabase.getMeltQuote(quoteId: quoteId) else {
                    clearTrackedOnchainMeltQuote(quoteId: quoteId)
                    continue
                }

                guard PaymentMethodKind.from(storedQuote.paymentMethod) == .onchain else {
                    clearTrackedOnchainMeltQuote(quoteId: quoteId)
                    continue
                }

                if (storedQuote.state == .paid || storedQuote.state == .issued),
                   storedQuote.usedByOperation == nil {
                    clearTrackedOnchainMeltQuote(quoteId: quoteId)
                    continue
                }

                guard storedQuote.usedByOperation != nil else {
                    continue
                }

                let wallet = try await repo.getWallet(
                    mintUrl: MintUrl(url: mintURLString),
                    unit: .sat
                )
                let status: OnchainMeltQuoteResponse = try await performOnchainRequest(
                    url: try onchainMeltQuoteURL(for: mintURLString, quoteId: quoteId),
                    method: "GET",
                    logContext: "Pending on-chain melt quote status \(quoteId)"
                )

                guard status.state == .paid || status.state == .issued else {
                    continue
                }

                AppLogger.wallet.info(
                    "Pending on-chain melt quote \(quoteId, privacy: .public) is \(status.state.rawValue, privacy: .public); recovering local wallet state"
                )
                _ = try await recoverPaidOnchainMelt(
                    quoteId: quoteId,
                    mintURLString: mintURLString,
                    status: status,
                    wallet: wallet,
                    walletDatabase: walletDatabase
                )
            } catch {
                AppLogger.wallet.error(
                    "Failed to recover pending on-chain melt quote \(quoteId, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func quoteStateLabel(_ state: QuoteState) -> String {
        switch state {
        case .unpaid:
            return "UNPAID"
        case .pending:
            return "PENDING"
        case .paid:
            return "PAID"
        case .issued:
            return "ISSUED"
        }
    }

    private func logStoredMintDiagnostics(
        quoteId: String,
        prefix: String
    ) async {
        guard let walletDatabase = walletDatabase() else {
            AppLogger.wallet.info(
                "\(prefix, privacy: .public): wallet database unavailable for quote \(quoteId, privacy: .public)"
            )
            return
        }

        do {
            guard let mintQuote = try await walletDatabase.getMintQuote(quoteId: quoteId) else {
                AppLogger.wallet.info(
                    "\(prefix, privacy: .public): no local mint quote found for \(quoteId, privacy: .public)"
                )
                return
            }

            let sagaExists: Bool
            if let operationId = mintQuote.usedByOperation {
                sagaExists = try await walletDatabase.getSaga(id: operationId) != nil
            } else {
                sagaExists = false
            }

            AppLogger.wallet.info(
                "\(prefix, privacy: .public): local mint quote \(quoteId, privacy: .public) state=\(self.quoteStateLabel(mintQuote.state), privacy: .public), payment_method=\(PaymentMethodKind.from(mintQuote.paymentMethod)?.rawValue ?? "unknown", privacy: .public), amount_paid=\(mintQuote.amountPaid.value, privacy: .public), amount_issued=\(mintQuote.amountIssued.value, privacy: .public), used_by_operation=\(mintQuote.usedByOperation ?? "<none>", privacy: .public), saga_exists=\(sagaExists, privacy: .public), version=\(mintQuote.version, privacy: .public)"
            )
        } catch {
            AppLogger.wallet.error(
                "\(prefix, privacy: .public): failed to inspect local mint diagnostics for \(quoteId, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func logStoredMeltDiagnostics(
        quoteId: String,
        prefix: String
    ) async {
        guard let walletDatabase = walletDatabase() else {
            AppLogger.wallet.info(
                "\(prefix, privacy: .public): wallet database unavailable for quote \(quoteId, privacy: .public)"
            )
            return
        }

        do {
            guard let meltQuote = try await walletDatabase.getMeltQuote(quoteId: quoteId) else {
                AppLogger.wallet.info(
                    "\(prefix, privacy: .public): no local melt quote found for \(quoteId, privacy: .public)"
                )
                return
            }

            let sagaExists: Bool
            if let operationId = meltQuote.usedByOperation {
                sagaExists = try await walletDatabase.getSaga(id: operationId) != nil
            } else {
                sagaExists = false
            }

            AppLogger.wallet.info(
                "\(prefix, privacy: .public): local melt quote \(quoteId, privacy: .public) state=\(self.quoteStateLabel(meltQuote.state), privacy: .public), payment_method=\(PaymentMethodKind.from(meltQuote.paymentMethod)?.rawValue ?? "unknown", privacy: .public), used_by_operation=\(meltQuote.usedByOperation ?? "<none>", privacy: .public), saga_exists=\(sagaExists, privacy: .public), version=\(meltQuote.version, privacy: .public)"
            )
        } catch {
            AppLogger.wallet.error(
                "\(prefix, privacy: .public): failed to inspect local melt diagnostics for \(quoteId, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func recoverPaidOnchainMelt(
        quoteId: String,
        mintURLString: String,
        status: OnchainMeltQuoteResponse,
        wallet: Wallet,
        walletDatabase: WalletSqliteDatabase
    ) async throws -> RecoveredOnchainMeltResult {
        guard let storedQuote = try await walletDatabase.getMeltQuote(quoteId: quoteId) else {
            AppLogger.wallet.error(
                "On-chain melt recovery could not find local quote \(quoteId, privacy: .public)"
            )
            clearTrackedOnchainMeltQuote(quoteId: quoteId)
            return RecoveredOnchainMeltResult(preimage: status.paymentProof, feePaid: 0)
        }

        let finalizedState: QuoteState = status.state == .issued ? .paid : status.quoteState

        if (storedQuote.state == .paid || storedQuote.state == .issued),
           storedQuote.usedByOperation == nil {
            clearTrackedOnchainMeltQuote(quoteId: quoteId)
            return RecoveredOnchainMeltResult(
                preimage: storedQuote.paymentProof ?? status.paymentProof,
                feePaid: 0
            )
        }

        let reservedProofs: [ProofInfo] = if let operationId = storedQuote.usedByOperation {
            try await walletDatabase.getReservedProofs(operationId: operationId)
        } else {
            []
        }
        let reservedProofYs = reservedProofs.map(\.y)
        let reservedAmount = reservedProofs.reduce(UInt64(0)) { partialResult, proofInfo in
            partialResult + proofInfo.proof.amount.value
        }
        let changeAmount = status.change?.reduce(UInt64(0)) { $0 + $1.amount } ?? 0
        let feePaid = reservedAmount >= status.amount + changeAmount
            ? reservedAmount - status.amount - changeAmount
            : 0

        AppLogger.wallet.info(
            "Recovering on-chain melt quote \(quoteId, privacy: .public): reserved_proof_count=\(reservedProofs.count, privacy: .public), reserved_amount=\(reservedAmount, privacy: .public), change_amount=\(changeAmount, privacy: .public), fee_paid=\(feePaid, privacy: .public)"
        )

        if !reservedProofYs.isEmpty {
            try await walletDatabase.updateProofsState(ys: reservedProofYs, state: .spent)
        }

        let recoveredQuote = MeltQuote(
            id: storedQuote.id,
            mintUrl: storedQuote.mintUrl,
            amount: storedQuote.amount,
            unit: storedQuote.unit,
            request: storedQuote.request,
            feeReserve: storedQuote.feeReserve,
            state: finalizedState,
            expiry: storedQuote.expiry,
            paymentProof: status.paymentProof ?? storedQuote.paymentProof,
            paymentMethod: storedQuote.paymentMethod,
            usedByOperation: storedQuote.usedByOperation,
            version: storedQuote.version
        )
        try await walletDatabase.addMeltQuote(quote: recoveredQuote)

        try await addRecoveredOnchainMeltTransactionIfNeeded(
            quoteId: quoteId,
            mintURLString: mintURLString,
            storedQuote: recoveredQuote,
            reservedProofs: reservedProofs,
            amount: status.amount,
            feePaid: feePaid,
            paymentProof: status.paymentProof
        )

        if storedQuote.usedByOperation != nil {
            scheduleOnchainMeltCleanup(
                quoteId: quoteId,
                finalizedState: finalizedState,
                wallet: wallet,
                walletDatabase: walletDatabase
            )
        } else {
            clearTrackedOnchainMeltQuote(quoteId: quoteId)
        }

        AppLogger.wallet.info(
            "On-chain melt quote \(quoteId, privacy: .public) local recovery persisted; returning control to the UI"
        )

        return RecoveredOnchainMeltResult(
            preimage: recoveredQuote.paymentProof,
            feePaid: feePaid
        )
    }

    private func addRecoveredOnchainMeltTransactionIfNeeded(
        quoteId: String,
        mintURLString: String,
        storedQuote: MeltQuote,
        reservedProofs: [ProofInfo],
        amount: UInt64,
        feePaid: UInt64,
        paymentProof: String?
    ) async throws {
        guard let walletDatabase = walletDatabase() else { return }

        let mintUrl = MintUrl(url: mintURLString)
        let existingTransactions = try await walletDatabase.listTransactions(
            mintUrl: mintUrl,
            direction: .outgoing,
            unit: .sat
        )
        guard !existingTransactions.contains(where: { $0.quoteId == quoteId }) else {
            return
        }

        let transaction = Transaction(
            id: TransactionId(hex: onchainMeltTransactionIDHex(for: quoteId)),
            mintUrl: mintUrl,
            direction: .outgoing,
            amount: Amount(value: amount),
            fee: Amount(value: feePaid),
            unit: .sat,
            ys: reservedProofs.map(\.y),
            timestamp: UInt64(Date().timeIntervalSince1970),
            memo: nil,
            metadata: ["recovery": "onchain-poll-fallback"],
            quoteId: quoteId,
            paymentRequest: storedQuote.request,
            paymentProof: paymentProof,
            paymentMethod: storedQuote.paymentMethod,
            sagaId: storedQuote.usedByOperation
        )
        try await walletDatabase.addTransaction(transaction: transaction)
    }

    private func scheduleOnchainMeltCleanup(
        quoteId: String,
        finalizedState: QuoteState,
        wallet: Wallet,
        walletDatabase: WalletSqliteDatabase
    ) {
        guard !onchainMeltCleanupInFlight.contains(quoteId) else {
            return
        }
        onchainMeltCleanupInFlight.insert(quoteId)

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.onchainMeltCleanupInFlight.remove(quoteId)
            }

            do {
                let restored = try await wallet.restore()
                AppLogger.wallet.info(
                    "On-chain melt recovery restore for quote \(quoteId, privacy: .public): spent=\(restored.spent.value, privacy: .public), unspent=\(restored.unspent.value, privacy: .public), pending=\(restored.pending.value, privacy: .public)"
                )

                guard let currentQuote = try await walletDatabase.getMeltQuote(quoteId: quoteId) else {
                    self.clearTrackedOnchainMeltQuote(quoteId: quoteId)
                    return
                }

                if let operationId = currentQuote.usedByOperation {
                    try await walletDatabase.deleteSaga(id: operationId)
                }

                let finalizedQuote = MeltQuote(
                    id: currentQuote.id,
                    mintUrl: currentQuote.mintUrl,
                    amount: currentQuote.amount,
                    unit: currentQuote.unit,
                    request: currentQuote.request,
                    feeReserve: currentQuote.feeReserve,
                    state: finalizedState,
                    expiry: currentQuote.expiry,
                    paymentProof: currentQuote.paymentProof,
                    paymentMethod: currentQuote.paymentMethod,
                    usedByOperation: nil,
                    version: currentQuote.version
                )
                try await walletDatabase.addMeltQuote(quote: finalizedQuote)
                self.clearTrackedOnchainMeltQuote(quoteId: quoteId)
                await self.onWalletStateUpdated()
            } catch {
                AppLogger.wallet.error(
                    "On-chain melt cleanup failed for quote \(quoteId, privacy: .public): \(String(describing: error), privacy: .public). Keeping saga metadata for a later retry."
                )
            }
        }
    }

    private func trackOnchainMeltQuote(quoteId: String, mintURLString: String) {
        var trackedQuotes = trackedOnchainMeltQuoteMintURLs()
        trackedQuotes[quoteId] = mintURLString
        UserDefaults.standard.set(trackedQuotes, forKey: StorageKeys.trackedOnchainMeltMintURLs)
    }

    private func clearTrackedOnchainMeltQuote(quoteId: String) {
        var trackedQuotes = trackedOnchainMeltQuoteMintURLs()
        trackedQuotes.removeValue(forKey: quoteId)
        UserDefaults.standard.set(trackedQuotes, forKey: StorageKeys.trackedOnchainMeltMintURLs)
    }

    private func trackedOnchainMeltQuoteMintURLs() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: StorageKeys.trackedOnchainMeltMintURLs) as? [String: String] ?? [:]
    }

    private func onchainMeltTransactionIDHex(for quoteId: String) -> String {
        SHA256.hash(data: Data("onchain-melt-\(quoteId)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func onchainMeltQuoteURL(for mintURLString: String, quoteId: String? = nil) throws -> URL {
        guard var url = URL(string: mintURLString) else {
            throw WalletError.networkError("Invalid mint URL.")
        }

        url.appendPathComponent("v1")
        url.appendPathComponent("melt")
        url.appendPathComponent("quote")
        url.appendPathComponent(PaymentMethodKind.onchain.rawValue)

        if let quoteId {
            url.appendPathComponent(quoteId)
        }

        return url
    }

    private func onchainMintQuoteURL(for mintURLString: String, quoteId: String? = nil) throws -> URL {
        guard var url = URL(string: mintURLString) else {
            throw WalletError.networkError("Invalid mint URL.")
        }

        url.appendPathComponent("v1")
        url.appendPathComponent("mint")
        url.appendPathComponent("quote")
        url.appendPathComponent(PaymentMethodKind.onchain.rawValue)

        if let quoteId {
            url.appendPathComponent(quoteId)
        }

        return url
    }

    private func makeStoredOnchainMeltQuote(
        response: OnchainMeltQuoteResponse,
        mintURLString: String,
        version: UInt32
    ) -> MeltQuote {
        MeltQuote(
            id: response.quote,
            mintUrl: MintUrl(url: mintURLString),
            amount: Amount(value: response.amount),
            unit: .sat,
            request: response.request,
            feeReserve: Amount(value: response.fee),
            state: response.quoteState,
            expiry: response.expiry ?? 0,
            paymentProof: response.paymentProof,
            paymentMethod: PaymentMethodKind.onchain.cdkMethod,
            usedByOperation: nil,
            version: version
        )
    }

    private func bitcoinNetwork(for mintURLString: String) -> BitcoinNetwork {
        guard let host = URL(string: mintURLString)?.host?.lowercased() else {
            return .bitcoin
        }

        if host == "onchain.cashudevkit.org"
            || host.contains("signet")
            || host.contains("mutinynet") {
            return .signet
        }

        if host.contains("regtest") {
            return .regtest
        }

        if host.contains("testnet") {
            return .testnet
        }

        return .bitcoin
    }

    private func currencyUnit(from unit: String?) -> CurrencyUnit? {
        switch unit?.lowercased() {
        case "sat":
            return .sat
        case "msat":
            return .msat
        case "usd":
            return .usd
        case "eur":
            return .eur
        case "auth":
            return .auth
        case let unit?:
            return .custom(unit: unit)
        case nil:
            return nil
        }
    }

}

private extension PaymentMethodKind {
    var subscriptionKind: SubscriptionKind? {
        switch self {
        case .bolt11:
            return .bolt11MintQuote
        case .bolt12:
            return .bolt12MintQuote
        case .onchain:
            return nil
        }
    }
}

private struct OnchainMeltQuoteRequestBody: Encodable {
    let request: String
    let unit = "sat"
    let amount: UInt64
}

private struct OnchainMintQuoteResponse: Decodable {
    let quote: String
    let request: String
    let unit: String?
    let amount: UInt64?
    let expiry: UInt64?
    let amountPaid: UInt64
    let amountIssued: UInt64

    enum CodingKeys: String, CodingKey {
        case quote
        case request
        case unit
        case amount
        case expiry
        case amountPaid = "amount_paid"
        case amountIssued = "amount_issued"
    }

    func quoteState(existingState: QuoteState) -> QuoteState {
        if amountPaid > 0, amountIssued >= amountPaid {
            return .issued
        }

        if amountPaid > amountIssued {
            return .paid
        }

        if existingState == .issued {
            return .issued
        }

        return .unpaid
    }
}

private struct OnchainMeltQuoteResponse: Decodable {
    let quote: String
    let request: String
    let amount: UInt64
    let fee: UInt64
    let state: OnchainQuoteResponseState
    let expiry: UInt64?
    let paymentProof: String?
    let change: [OnchainMeltQuoteChange]?

    enum CodingKeys: String, CodingKey {
        case quote
        case request
        case amount
        case fee
        case state
        case expiry
        case paymentProof = "payment_proof"
        case paymentPreimage = "payment_preimage"
        case change
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quote = try container.decode(String.self, forKey: .quote)
        request = try container.decode(String.self, forKey: .request)
        amount = try container.decode(UInt64.self, forKey: .amount)
        fee = try container.decode(UInt64.self, forKey: .fee)
        state = try container.decode(OnchainQuoteResponseState.self, forKey: .state)
        expiry = try container.decodeIfPresent(UInt64.self, forKey: .expiry)
        paymentProof = try container.decodeIfPresent(String.self, forKey: .paymentProof)
            ?? container.decodeIfPresent(String.self, forKey: .paymentPreimage)
        change = try container.decodeIfPresent([OnchainMeltQuoteChange].self, forKey: .change)
    }

    var quoteState: QuoteState {
        state.quoteState
    }
}

private struct OnchainMeltQuoteChange: Decodable {
    let amount: UInt64
}

private enum OnchainQuoteResponseState: String, Decodable {
    case unpaid = "UNPAID"
    case pending = "PENDING"
    case paid = "PAID"
    case issued = "ISSUED"

    var quoteState: QuoteState {
        switch self {
        case .unpaid:
            return .unpaid
        case .pending:
            return .pending
        case .paid:
            return .paid
        case .issued:
            return .issued
        }
    }
}

private struct OnchainMintErrorResponse: Decodable {
    let detail: String?
}
