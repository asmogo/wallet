import Foundation
import CashuDevKit

// MARK: - Lightning Service

/// Service responsible for Lightning Network operations (NUT-04/NUT-05).
/// Handles minting (receiving via Lightning) and melting (paying via Lightning).
@MainActor
class LightningService: ObservableObject {
    private enum QuoteExpiry {
        static let never: UInt64 = 0
        static let localNeverExpiresSentinel: UInt64 = 253_402_300_799
    }

    // MARK: - Published Properties
    
    /// Whether an operation is in progress
    @Published var isLoading = false
    
    // MARK: - Dependencies
    
    private let walletRepository: () -> WalletRepository?
    private let walletDatabase: () -> WalletSqliteDatabase?
    private let getActiveMint: () -> MintInfo?
    private var mintQuotesInFlight: Set<String> = []
    
    // MARK: - Initialization
    
    init(
        walletRepository: @escaping () -> WalletRepository?,
        walletDatabase: @escaping () -> WalletSqliteDatabase?,
        getActiveMint: @escaping () -> MintInfo?
    ) {
        self.walletRepository = walletRepository
        self.walletDatabase = walletDatabase
        self.getActiveMint = getActiveMint
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

        if let walletDatabase = walletDatabase(),
           let existingQuote = try await walletDatabase.getMintQuote(quoteId: quoteId) {
            let storedPaymentMethod = PaymentMethodKind.from(existingQuote.paymentMethod)

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
            let refreshedQuote = mintQuoteForLocalStorage(
                mintQuotePreservingLocalMetadata(quote, from: existingQuote),
                paymentMethod: paymentMethod,
                fallbackAmount: existingQuote.amount?.value
            )
            await persistMintQuote(refreshedQuote)
            return mintQuoteInfo(
                from: refreshedQuote,
                fallbackAmount: existingQuote.amount?.value,
                paymentMethod: paymentMethod
            )
        }

        guard let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }

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
                do {
                    try await walletDatabase.releaseMintQuote(operationId: operationId)
                    try? await walletDatabase.deleteSaga(id: operationId)
                    if let refreshedQuote = try await walletDatabase.getMintQuote(quoteId: quoteId),
                       refreshedQuote.usedByOperation != nil {
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
        } else if let activeMint = getActiveMint() {
            mintUrl = MintUrl(url: activeMint.url)
            amountSplitTarget = .none
        } else {
            throw WalletError.notInitialized
        }

        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
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
        guard let repo = walletRepository(),
              let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let normalizedAddress = PaymentRequestParser.normalizeBitcoinRequest(address)
        let quoteOptions = try await wallet.quoteOnchainMeltOptions(
            address: normalizedAddress,
            amount: Amount(value: amount),
            maxFeeAmount: nil
        )

        guard let quoteOption = quoteOptions.first else {
            throw WalletError.networkError("Mint returned no on-chain melt fee options.")
        }

        let quote = try await wallet.selectOnchainMeltQuote(quote: quoteOption)

        return meltQuoteInfo(from: quote, paymentMethod: .onchain)
    }

    func subscribeToMintQuote(
        quoteId: String,
        paymentMethod: PaymentMethodKind
    ) async throws -> ActiveSubscription? {
        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }

        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let params = SubscribeParams(kind: paymentMethod.subscriptionKind, filters: [quoteId], id: nil)
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
            ? storedMeltQuote?.mintUrl?.url ?? activeMint.url
            : activeMint.url
        let mintUrl = MintUrl(url: mintURLString)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)

        let preparedMelt = try await wallet.prepareMelt(quoteId: quoteId)
        let result = try await preparedMelt.confirm()
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
            state: mintQuoteState(from: quote, paymentMethod: paymentMethod),
            expiry: displayExpiry(quote.expiry)
        )
    }

    private func mintQuoteState(
        from quote: MintQuote,
        paymentMethod: PaymentMethodKind
    ) -> MintQuoteState {
        if quote.amountPaid.value > 0, quote.amountIssued.value >= quote.amountPaid.value {
            return .issued
        }

        if quote.amountPaid.value > quote.amountIssued.value {
            return .paid
        }

        guard paymentMethod == .bolt11 else {
            return .pending
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
            estimatedBlocks: quote.estimatedBlocks,
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
            estimatedBlocks: quote.estimatedBlocks,
            paymentMethod: quote.paymentMethod,
            secretKey: quote.secretKey,
            usedByOperation: nil,
            version: quote.version
        )
    }

    private func mintQuotePreservingLocalMetadata(
        _ quote: MintQuote,
        from existingQuote: MintQuote
    ) -> MintQuote {
        let request = quote.request.isEmpty ? existingQuote.request : quote.request
        let amount = quote.amount ?? existingQuote.amount
        let expiry = quote.expiry == QuoteExpiry.never && existingQuote.expiry != QuoteExpiry.never
            ? existingQuote.expiry
            : quote.expiry
        let paymentMethod = PaymentMethodKind.from(quote.paymentMethod) == nil
            ? existingQuote.paymentMethod
            : quote.paymentMethod

        return MintQuote(
            id: quote.id,
            amount: amount,
            unit: quote.unit,
            request: request,
            state: quote.state,
            expiry: expiry,
            mintUrl: quote.mintUrl,
            amountIssued: quote.amountIssued,
            amountPaid: quote.amountPaid,
            estimatedBlocks: quote.estimatedBlocks ?? existingQuote.estimatedBlocks,
            paymentMethod: paymentMethod,
            secretKey: quote.secretKey ?? existingQuote.secretKey,
            usedByOperation: quote.usedByOperation ?? existingQuote.usedByOperation,
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
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let wallet = try await repo.getWallet(mintUrl: existingQuote.mintUrl, unit: .sat)
        let checkedQuote = try await wallet.checkMintQuoteStatus(quoteId: existingQuote.id)
        let refreshedQuote = mintQuoteForLocalStorage(
            mintQuotePreservingLocalMetadata(checkedQuote, from: existingQuote),
            paymentMethod: .onchain,
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

}

private extension PaymentMethodKind {
    var subscriptionKind: SubscriptionKind {
        switch self {
        case .bolt11:
            return .bolt11MintQuote
        case .bolt12:
            return .bolt12MintQuote
        case .onchain:
            return .onchainMintQuote
        }
    }
}
