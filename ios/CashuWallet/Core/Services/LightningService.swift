import Foundation
import Cdk

struct MintQuoteWalletContext: Equatable {
    let mintURL: String
    let unit: Cdk.CurrencyUnit
}

/// Keeps every operation on the wallet that owns the quote. Missing persisted
/// context fails closed rather than guessing from mutable active-wallet state.
enum MintQuoteContextPolicy {
    static func context(for quote: MintQuote) -> MintQuoteWalletContext {
        MintQuoteWalletContext(mintURL: quote.mintUrl.url, unit: quote.unit)
    }

    static func existingAmountlessOffer(
        in quotes: [MintQuote],
        requestedContext: MintQuoteWalletContext
    ) -> MintQuote? {
        quotes.first {
            PaymentMethodKind.from($0.paymentMethod) == .bolt12
                && $0.amount == nil
                && context(for: $0) == requestedContext
        }
    }

    static func walletContext(storedQuote: MintQuote?) -> MintQuoteWalletContext? {
        storedQuote.map { context(for: $0) }
    }
}

/// Builds CDK's explicit amount override for a request that does not carry one.
/// Keeping this small conversion outside the service makes the protocol boundary
/// directly testable without a live wallet repository.
func meltOptionsForLightningRequest(
    requestAmountMsat: UInt64?,
    amountSats: UInt64?
) throws -> MeltOptions? {
    guard requestAmountMsat == nil else { return nil }
    guard let amountSats, amountSats > 0 else {
        throw WalletError.networkError(
            "This Lightning request doesn't include an amount. Enter an amount before requesting a quote."
        )
    }
    guard amountSats <= UInt64.max / 1_000 else {
        throw WalletError.networkError("Amount is too large.")
    }
    return .amountless(amountMsat: Amount(value: amountSats * 1_000))
}

// MARK: - Lightning Service

/// Service responsible for Lightning Network operations (NUT-04/NUT-05).
/// Handles minting (receiving via Lightning) and melting (paying via Lightning).
@MainActor
class LightningService: ObservableObject {
    static func requiredMeltAmount(amount: UInt64, feeReserve: UInt64) throws -> UInt64 {
        let total = amount.addingReportingOverflow(feeReserve)
        guard !total.overflow else {
            throw WalletError.networkError("The mint returned an invalid payment amount or fee.")
        }
        return total.partialValue
    }

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
    private let getMints: () -> [MintInfo]
    private var mintQuotesInFlight: Set<String> = []
    
    // MARK: - Initialization
    
    init(
        walletRepository: @escaping () -> WalletRepository?,
        walletDatabase: @escaping () -> WalletSqliteDatabase?,
        getActiveMint: @escaping () -> MintInfo?,
        getMints: @escaping () -> [MintInfo] = { [] }
    ) {
        self.walletRepository = walletRepository
        self.walletDatabase = walletDatabase
        self.getActiveMint = getActiveMint
        self.getMints = getMints
    }

    func clearState() {
        isLoading = false
        mintQuotesInFlight.removeAll()
    }
    
    // MARK: - Minting (NUT-04) - Receive via Lightning
    
    /// Create a mint quote for the requested payment method.
    /// - Parameters:
    ///   - amount: Amount in satoshis when required by the payment method
    ///   - method: The payment method to use for the quote
    /// - Returns: Mint quote with request details
    /// - Parameter targetMintURL: mint the quote is created at. Defaults to the
    ///   active mint (existing callers). Pass an explicit URL to mint at a
    ///   specific mint — e.g. funding a freshly-added mint to pay a Cashu request.
    ///   Honored for all supported payment methods.
    func createMintQuote(
        amount: UInt64?,
        method: PaymentMethodKind = .bolt11,
        targetMintURL: String? = nil,
        unit: Cdk.CurrencyUnit = .sat,
        description: String? = nil
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
            return try await createOnchainMintQuote(mintURL: targetMintURL ?? activeMint.url)
        }

        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let mintUrl = MintUrl(url: targetMintURL ?? activeMint.url)
        // Mint into the selected unit's wallet (amount is in that unit's base
        // units). Ensure a non-sat per-unit wallet exists first (sat is always
        // tracked) — mirrors TokenService.sendTokens.
        if PaymentRequestDecoder.unitDescription(unit) != "sat" {
            try await repo.createWallet(mintUrl: mintUrl, unit: unit, targetProofCount: nil)
        }
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: unit)

        let quote = try await wallet.mintQuote(
            paymentMethod: method.cdkMethod,
            amount: amount.map { Amount(value: $0) },
            // Description is only threaded for BOLT12 offers (NUT-04 optional);
            // mint support on other rails is uneven, so they keep nil.
            description: method == .bolt12 ? description : nil,
            extra: nil
        )

        await persistMintQuote(quote, paymentMethod: method)

        var info = mintQuoteInfo(from: quote, fallbackAmount: amount, paymentMethod: method)
        info.description = method == .bolt12 ? description : nil
        return info
    }

    /// Returns the pending amountless BOLT12 offer matching `description`
    /// (nil → the plain, description-less offer), or nil if none exists.
    /// Used to avoid creating a new offer on every visit to the Reusable
    /// Invoice screen. CDK never returns offer descriptions, so the match
    /// joins quotes with the locally stored quote-intent memos by quote id —
    /// keeping reuse unambiguous once several amountless offers exist (offers
    /// are immutable, so a changed description always mints a fresh one).
    func existingAmountlessOffer(mintURL: String, unit: Cdk.CurrencyUnit, description: String? = nil) async throws -> MintQuoteInfo? {
        guard let db = walletDatabase() else { return nil }
        let pendingQuotes = try await db.getUnissuedMintQuotes()
        let memosByQuoteId = Dictionary(
            CashuRequestStore.shared.requests.compactMap { request in
                request.quoteId.map { ($0, request.memo) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard let match = pendingQuotes.first(where: {
            MintQuoteDomain.isReusableAmountlessOffer(
                paymentMethod: PaymentMethodKind.from($0.paymentMethod),
                isAmountless: $0.amount == nil,
                quoteMintUrl: $0.mintUrl.url,
                quoteUnit: PaymentRequestDecoder.unitDescription($0.unit),
                activeMintUrl: mintURL,
                unit: PaymentRequestDecoder.unitDescription(unit),
                storedMemo: memosByQuoteId[$0.id] ?? nil,
                description: description
            )
        }) else { return nil }
        var info = mintQuoteInfo(from: match, fallbackAmount: nil, paymentMethod: .bolt12)
        info.description = description
        return info
    }

    /// Returns an existing unpaid onchain quote at the active mint, or nil if none exists.
    /// Used to avoid generating a fresh deposit address on every visit to the onchain receive screen.
    func existingOnchainMintQuote(mintURL: String? = nil) async throws -> MintQuoteInfo? {
        guard let db = walletDatabase(),
              let mintURL = mintURL ?? getActiveMint()?.url else { return nil }
        let pendingQuotes = try await db.getUnissuedMintQuotes()
        guard let match = pendingQuotes.first(where: {
            PaymentMethodKind.from($0.paymentMethod) == .onchain
            && MintURLIdentity.normalized($0.mintUrl.url) == MintURLIdentity.normalized(mintURL)
            && $0.amountPaid.value == 0
        }) else { return nil }
        let info = mintQuoteInfo(from: match, fallbackAmount: nil, paymentMethod: .onchain)
        return info.isExpired ? nil : info
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

            let context = MintQuoteContextPolicy.context(for: existingQuote)
            let wallet = try await repo.getWallet(
                mintUrl: MintUrl(url: context.mintURL),
                unit: context.unit
            )
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

        throw WalletError.networkError(
            "The mint context for this receive request is unavailable. Create a new request and try again."
        )
    }

    /// Last durable local quote snapshot without contacting the mint. Recovery
    /// uses this only to tell the truth after a status request fails: a cached
    /// paid/issued delta is enough to say that ecash is still pending, but never
    /// enough to claim success.
    func storedMintQuote(quoteId: String) async -> MintQuoteInfo? {
        guard let database = walletDatabase() else { return nil }
        let quote: MintQuote
        do {
            guard let stored = try await database.getMintQuote(quoteId: quoteId) else {
                return nil
            }
            quote = stored
        } catch {
            return nil
        }
        let method = PaymentMethodKind.from(quote.paymentMethod) ?? .bolt11
        return mintQuoteInfo(
            from: quote,
            fallbackAmount: quote.amount?.value,
            paymentMethod: method
        )
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
        // Redeem into the quote's own unit wallet (also makes resuming a
        // persisted non-sat quote correct). Never guess from the active wallet.
        let quoteUnit: Cdk.CurrencyUnit

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
            amountSplitTarget = .none
            quoteUnit = normalizedQuote.unit

            if storedPaymentMethod == .onchain,
               normalizedQuote.amountPaid.value <= normalizedQuote.amountIssued.value {
                throw WalletError.networkError(
                    "Mint has not credited this on-chain quote yet (amount_paid=\(normalizedQuote.amountPaid.value), amount_issued=\(normalizedQuote.amountIssued.value))."
                )
            }

            if storedPaymentMethod == .bolt12 {
                await persistMintQuoteIfNeeded(normalizedQuote, paymentMethod: .bolt12)
            }

            if normalizedQuote.usedByOperation != nil {
                let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: quoteUnit)
                let recoveredAmount = try await MintQuoteRecovery.reconcile(
                    quote: normalizedQuote,
                    recover: { _ = try await wallet.recoverIncompleteSagas() },
                    reload: { try await walletDatabase.getMintQuote(quoteId: quoteId) }
                )
                if recoveredAmount > 0 { return recoveredAmount }
            }
        } else {
            throw WalletError.networkError(
                "The mint context for this receive request is unavailable. Create a new request and try again."
            )
        }

        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: quoteUnit)
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
    func createMeltQuote(
        request: String,
        amount: UInt64? = nil,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }
        
        isLoading = true
        defer { isLoading = false }

        guard let metadata = await CdkRuntime.shared.lightningMetadata(from: request) else {
            if PaymentRequestParser.isBitcoinAddress(request) {
                throw WalletError.networkError("On-chain payments require an amount before requesting a quote.")
            }
            throw WalletError.networkError("Invalid Lightning payment request.")
        }

        let normalizedRequest = metadata.normalizedRequest
        let paymentMethod = metadata.paymentMethod
        let invoiceAmountSats = metadata.amountSats
        let meltOptions = try meltOptionsForLightningRequest(
            requestAmountMsat: metadata.amountMsat,
            amountSats: amount
        )

        if PaymentRequestParser.isBitcoinAddress(normalizedRequest) {
            throw WalletError.networkError("On-chain payments require an amount before requesting a quote.")
        }

        let candidates = meltQuoteCandidateMints(
            paymentMethod: paymentMethod,
            minimumAmount: invoiceAmountSats ?? amount,
            preferredMintURL: preferredMintURL
        )

        guard !candidates.isEmpty else {
            throw WalletError.networkError("No mint supports \(paymentMethod.displayName) payments.")
        }

        var lastError: Error?
        for mint in candidates {
            do {
                let mintUrl = MintUrl(url: mint.url)
                let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
                AppLogger.wallet.info(
                    "wallet-op native-call kind=meltQuote resource=\(WalletOperationCoordinator.privacySafeIdentifier(mint.url), privacy: .public) method=\(paymentMethod.rawValue, privacy: .public)"
                )
                let quote = try await wallet.meltQuote(
                    method: paymentMethod.cdkMethod,
                    request: normalizedRequest,
                    options: meltOptions,
                    extra: nil
                )

                let totalRequired = try Self.requiredMeltAmount(amount: quote.amount.value, feeReserve: quote.feeReserve.value)
                guard mint.balance >= totalRequired else {
                    lastError = NFCPaymentError.insufficientBalance(required: totalRequired, available: mint.balance)
                    continue
                }

                return meltQuoteInfo(from: quote, paymentMethod: paymentMethod, fallbackMintUrl: mint.url)
            } catch {
                lastError = error
                AppLogger.wallet.error(
                    "melt quote failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(mint.url), privacy: .public) method=\(paymentMethod.rawValue, privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }

        if let lastError {
            throw lastError
        }
        throw WalletError.networkError("No mint could create a melt quote for this payment request.")
    }
    
    /// Backward-compatible wrapper for older bolt11-specific call sites.
    func createMeltQuote(
        invoice: String,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        try await createMeltQuote(request: invoice, amount: nil, preferredMintURL: preferredMintURL)
    }
    
    /// Create a melt quote for paying a human-readable address.
    ///
    /// Resolves the address as a Lightning Address (LUD-16 / LNURL-pay) first. If the
    /// domain serves no LNURL-pay endpoint, falls back to CDK's `meltHumanReadable`,
    /// which resolves BIP-353 names (DNS-published BOLT12 offers).
    /// - Parameters:
    ///   - address: The user@domain address
    ///   - amount: Amount in satoshis
    /// - Returns: Melt quote with fee information
    func createHumanReadableMeltQuote(
        address: String,
        amount: UInt64,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        guard amount <= UInt64.max / 1000 else {
            throw WalletError.networkError("Amount is too large.")
        }
        let amountMsat = amount * 1000

        do {
            let resolvedLightningInvoice = try await LightningAddressResolver.resolveBolt11Invoice(
                address: address,
                amountMsat: amountMsat
            )
            return try await lightningAddressMeltQuote(
                invoice: resolvedLightningInvoice,
                amount: amount,
                preferredMintURL: preferredMintURL,
                repo: repo
            )
        } catch let resolverError as LightningAddressResolverError where resolverError.indicatesNoLnurlPayEndpoint {
            do {
                return try await bip353MeltQuote(
                    address: address,
                    amount: amount,
                    preferredMintURL: preferredMintURL,
                    repo: repo
                )
            } catch {
                AppLogger.wallet.error(
                    "BIP-353 fallback failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
                throw resolverError
            }
        }
    }

    private func lightningAddressMeltQuote(
        invoice: String,
        amount: UInt64,
        preferredMintURL: String?,
        repo: WalletRepository
    ) async throws -> MeltQuoteInfo {
        let candidates = meltQuoteCandidateMints(
            paymentMethod: .bolt11,
            minimumAmount: amount,
            preferredMintURL: preferredMintURL
        )

        guard !candidates.isEmpty else {
            throw WalletError.networkError("No mint supports Lightning payments.")
        }

        var lastError: Error?
        for mint in candidates {
            do {
                let mintUrl = MintUrl(url: mint.url)
                let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
                AppLogger.wallet.info(
                    "wallet-op native-call kind=meltQuote resource=\(WalletOperationCoordinator.privacySafeIdentifier(mint.url), privacy: .public) method=bolt11"
                )
                let quote = try await wallet.meltQuote(
                    method: PaymentMethodKind.bolt11.cdkMethod,
                    request: invoice,
                    options: nil,
                    extra: nil
                )

                let totalRequired = try Self.requiredMeltAmount(amount: quote.amount.value, feeReserve: quote.feeReserve.value)
                guard mint.balance >= totalRequired else {
                    lastError = NFCPaymentError.insufficientBalance(required: totalRequired, available: mint.balance)
                    continue
                }

                return meltQuoteInfo(from: quote, paymentMethod: .bolt11, fallbackMintUrl: mint.url)
            } catch {
                lastError = error
                AppLogger.wallet.error(
                    "Lightning address melt quote failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(mint.url), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }

        if let lastError {
            throw lastError
        }
        throw WalletError.networkError("No mint could create a melt quote for this Lightning address.")
    }

    /// Fallback for human-readable addresses without an LNURL-pay endpoint (BIP-353 names).
    /// BIP-353 resolves to a BOLT12 offer, so only bolt12-capable mints are candidates.
    private func bip353MeltQuote(
        address: String,
        amount: UInt64,
        preferredMintURL: String?,
        repo: WalletRepository
    ) async throws -> MeltQuoteInfo {
        let candidates = meltQuoteCandidateMints(
            paymentMethod: .bolt12,
            minimumAmount: amount,
            preferredMintURL: preferredMintURL
        )

        guard !candidates.isEmpty else {
            throw WalletError.networkError("No mint supports BOLT12 payments required for this address.")
        }

        var lastError: Error?
        for mint in candidates {
            do {
                let mintUrl = MintUrl(url: mint.url)
                let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
                AppLogger.wallet.info(
                    "wallet-op native-call kind=meltQuote resource=\(WalletOperationCoordinator.privacySafeIdentifier(mint.url), privacy: .public) method=bolt12"
                )
                let quote = try await wallet.meltHumanReadable(
                    address: address,
                    amountMsat: Amount(value: amount * 1000),
                    network: bitcoinNetwork(for: mint.url)
                )

                let totalRequired = try Self.requiredMeltAmount(amount: quote.amount.value, feeReserve: quote.feeReserve.value)
                guard mint.balance >= totalRequired else {
                    lastError = NFCPaymentError.insufficientBalance(required: totalRequired, available: mint.balance)
                    continue
                }

                let paymentMethod = PaymentMethodKind.from(quote.paymentMethod) ?? .bolt12
                return meltQuoteInfo(from: quote, paymentMethod: paymentMethod, fallbackMintUrl: mint.url)
            } catch {
                lastError = error
                AppLogger.wallet.error(
                    "BIP-353 melt quote failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(mint.url), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }

        if let lastError {
            throw lastError
        }
        throw WalletError.networkError("No mint could create a melt quote for this address.")
    }

    func createOnchainMeltQuote(
        address: String,
        amount: UInt64,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        let normalizedAddress = PaymentRequestParser.normalizeBitcoinRequest(address)
        let candidates = meltQuoteCandidateMints(
            paymentMethod: .onchain,
            minimumAmount: amount,
            preferredMintURL: preferredMintURL
        )

        guard !candidates.isEmpty else {
            throw WalletError.networkError("No mint supports On-chain payments.")
        }

        var lastError: Error?
        for mint in candidates {
            do {
                let mintUrl = MintUrl(url: mint.url)
                let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
                AppLogger.wallet.info(
                    "wallet-op native-call kind=meltQuote resource=\(WalletOperationCoordinator.privacySafeIdentifier(mint.url), privacy: .public) method=onchain"
                )
                let quoteOptions = try await wallet.quoteOnchainMeltOptions(
                    address: normalizedAddress,
                    amount: Amount(value: amount),
                    maxFeeAmount: nil
                )

                guard let quoteOption = quoteOptions.first else {
                    lastError = WalletError.networkError("Mint returned no on-chain melt fee options.")
                    continue
                }

                let quote = try await wallet.selectOnchainMeltQuote(quote: quoteOption)
                let totalRequired = try Self.requiredMeltAmount(amount: quote.amount.value, feeReserve: quote.feeReserve.value)
                guard mint.balance >= totalRequired else {
                    lastError = NFCPaymentError.insufficientBalance(required: totalRequired, available: mint.balance)
                    continue
                }

                return meltQuoteInfo(from: quote, paymentMethod: .onchain, fallbackMintUrl: mint.url)
            } catch {
                lastError = error
                AppLogger.wallet.error(
                    "on-chain melt quote failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(mint.url), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }

        if let lastError {
            throw lastError
        }
        throw WalletError.networkError("No mint could create a melt quote for this on-chain payment.")
    }

    func subscribeToMintQuote(
        quoteId: String,
        paymentMethod: PaymentMethodKind
    ) async throws -> ActiveSubscription? {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let storedQuote: MintQuote?
        if let database = walletDatabase() {
            storedQuote = try await database.getMintQuote(quoteId: quoteId)
        } else {
            storedQuote = nil
        }

        guard let context = MintQuoteContextPolicy.walletContext(storedQuote: storedQuote) else {
            throw WalletError.networkError(
                "The mint context for this receive request is unavailable. Create a new request and try again."
            )
        }

        let wallet = try await repo.getWallet(
            mintUrl: MintUrl(url: context.mintURL),
            unit: context.unit
        )
        let params = SubscribeParams(kind: paymentMethod.subscriptionKind, filters: [quoteId], id: nil)
        return try await wallet.subscribe(params: params)
    }

    private func meltQuoteCandidateMints(
        paymentMethod: PaymentMethodKind,
        minimumAmount: UInt64?,
        preferredMintURL: String? = nil
    ) -> [MintInfo] {
        let activeMint = getActiveMint()
        let allMints = getMints()
        let mints = allMints.isEmpty
            ? activeMint.map { [$0] } ?? []
            : allMints

        if let preferredMintURL,
           let preferredMint = preferredMeltMint(
               for: preferredMintURL,
               activeMint: activeMint,
               mints: mints
           ) {
            guard preferredMint.supportedMeltMethods.contains(paymentMethod) else {
                return []
            }
            return [preferredMint]
        }

        let compatibleMints = mints.filter { $0.supportedMeltMethods.contains(paymentMethod) }
        guard !compatibleMints.isEmpty else {
            return []
        }

        let affordableCandidates = compatibleMints.filter { mint in
            guard let minimumAmount else { return true }
            return mint.balance >= minimumAmount
        }
        let candidates = affordableCandidates.isEmpty ? compatibleMints : affordableCandidates

        var ordered: [MintInfo] = []
        if let activeMint,
           candidates.contains(where: { $0.id == activeMint.id }) {
            let activeCanCover = minimumAmount.map { activeMint.balance >= $0 } ?? true
            if activeCanCover {
                ordered.append(activeMint)
            }
        }

        if ordered.isEmpty,
           let activeMint,
           candidates.contains(where: { $0.id == activeMint.id }) {
            ordered.append(activeMint)
        }

        ordered.append(contentsOf: candidates
            .filter { candidate in !ordered.contains(where: { $0.id == candidate.id }) }
            .sorted { lhs, rhs in
                if lhs.balance == rhs.balance {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.balance > rhs.balance
            }
        )

        return ordered
    }

    private func preferredMeltMint(
        for preferredMintURL: String,
        activeMint: MintInfo?,
        mints: [MintInfo]
    ) -> MintInfo? {
        let normalizedPreferredURL = normalizedMintURL(preferredMintURL)
        if let mint = mints.first(where: {
            normalizedMintURL($0.url) == normalizedPreferredURL
        }) {
            return mint
        }

        guard let activeMint,
              normalizedMintURL(activeMint.url) == normalizedPreferredURL else {
            return nil
        }

        return activeMint
    }

    private func normalizedMintURL(_ urlString: String) -> String {
        MintURLIdentity.normalized(urlString)
    }
    
    /// Outcome of a melt confirmation. Pending results are persisted and
    /// reconciled by the manager's serialized foreground poll.
    struct MeltConfirmation {
        let result: MeltPaymentResult
        /// Set when a lightning settlement wait outlived its cap: the
        /// still-running `PendingMelt.wait()` task (Swift's CDK bindings can't
        /// cancel a Rust future, so the racer abandons it rather than stopping
        /// it). The manager observes it to refresh balance/history the moment
        /// settlement lands; durable reconciliation stays with the coordinated
        /// foreground poll.
        var deferredSettlement: Task<FinalizedMelt, any Error>? = nil
    }

    /// Ceiling on how long a lightning melt may hold the repository lane while
    /// CDK's `PendingMelt.wait()` drives settlement. A fallback exit, not a
    /// polling knob — `wait()` polls the mint internally; this only bounds how
    /// long the send screen (and the exclusive wallet lane) stay committed
    /// before the pending face takes over. Kept under the coordinator's 30s
    /// log-only watchdog plus the confirm round-trips already spent.
    private enum MeltSettlementWait {
        static let cap: Duration = .seconds(30)
    }

    /// How a bounded settlement wait ended.
    enum BoundedMeltWaitOutcome {
        case finalized(FinalizedMelt)
        case failed(any Error)
        /// The cap fired first. The wait task keeps running — see
        /// `MeltConfirmation.deferredSettlement` — and becomes the post-cap
        /// settlement watcher (the shape Android has always run in
        /// `watchPendingMelt`).
        case capExpired(residual: Task<FinalizedMelt, any Error>)
    }

    /// Race CDK's settlement wait against a cap. No app-side polling — the
    /// injected `wait` (CDK's `PendingMelt.wait()`) polls internally; the cap
    /// exists only so a genuinely stuck payment (a held HTLC can hang for
    /// minutes) hands the screen back to the pending face instead of pinning
    /// the wallet lane. Injected as a closure so tests can drive all three
    /// outcomes without a CDK runtime.
    func awaitMeltSettlementBounded(
        cap: Duration,
        wait: @escaping () async throws -> FinalizedMelt
    ) async -> BoundedMeltWaitOutcome {
        // Both racers inherit this service's MainActor isolation, so the gate
        // is serialized; it exists because both will reach it.
        final class ResumeGate { var resumed = false }
        let gate = ResumeGate()
        let waitTask = Task { try await wait() }
        return await withCheckedContinuation { continuation in
            func resumeOnce(_ outcome: BoundedMeltWaitOutcome) {
                guard !gate.resumed else { return }
                gate.resumed = true
                continuation.resume(returning: outcome)
            }
            Task {
                do {
                    let finalized = try await waitTask.value
                    resumeOnce(.finalized(finalized))
                } catch {
                    resumeOnce(.failed(error))
                }
            }
            Task {
                try? await Task.sleep(for: cap)
                resumeOnce(.capExpired(residual: waitTask))
            }
        }
    }

    /// Terminal-melt mapping shared by the immediate `.paid` confirmation and a
    /// settlement wait that finished within the cap.
    private func settledMeltConfirmation(
        from finalized: FinalizedMelt,
        mintURLString: String
    ) -> MeltConfirmation {
        MeltConfirmation(
            result: MeltPaymentResult(
                preimage: finalized.preimage,
                amount: finalized.amount.value,
                feePaid: finalized.feePaid.value,
                mintUrl: mintURLString,
                settlement: .settled
            )
        )
    }

    /// Pending result built from the stored quote's numbers. Amount and fee
    /// aren't final until the payment settles, so the fee is the reserve upper
    /// bound — the UI still gets facts to show.
    private func pendingMeltConfirmation(
        storedMeltQuote: MeltQuote?,
        mintURLString: String,
        deferredSettlement: Task<FinalizedMelt, any Error>? = nil
    ) -> MeltConfirmation {
        MeltConfirmation(
            result: MeltPaymentResult(
                preimage: nil,
                amount: storedMeltQuote?.amount.value ?? 0,
                feePaid: storedMeltQuote?.feeReserve.value ?? 0,
                mintUrl: mintURLString,
                settlement: .pending
            ),
            deferredSettlement: deferredSettlement
        )
    }

    /// Pay a Lightning invoice or on-chain address (melt tokens)
    /// - Parameter quoteId: The quote ID to melt
    /// - Returns: Melt confirmation, including whether settlement is pending.
    func meltTokens(quoteId: String, mintUrl preferredMintUrl: String? = nil) async throws -> MeltConfirmation {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        let storedMeltQuote = try await walletDatabase()?.getMeltQuote(quoteId: quoteId)
        guard let mintURLString = preferredMintUrl ?? storedMeltQuote?.mintUrl?.url ?? getActiveMint()?.url else {
            throw WalletError.notInitialized
        }
        let mintUrl = MintUrl(url: mintURLString)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)

        let preparedMelt: PreparedMelt
        do {
            preparedMelt = try await wallet.prepareMelt(quoteId: quoteId)
        } catch {
            // Preparation can reserve proofs before its native future reports an
            // error. If CDK persisted an operation, resolve it exactly like an
            // interrupted confirmation instead of treating the quote as reusable.
            guard let database = walletDatabase() else {
                throw MeltPaymentRecoveryError.unresolved(
                    quoteID: quoteId,
                    mintURL: mintURLString,
                    operationID: "unknown"
                )
            }
            var reservedOperationID: String?
            do {
                let reservedQuote = try await database.getMeltQuote(quoteId: quoteId)
                reservedOperationID = reservedQuote?.usedByOperation
            } catch {
                // A failed read cannot establish that prepareMelt left no
                // reservation. Keep the outcome ambiguous and block a
                // potentially duplicate retry until status can be checked.
                throw MeltPaymentRecoveryError.unresolved(
                    quoteID: quoteId,
                    mintURL: mintURLString,
                    operationID: "unknown"
                )
            }
            guard let operationID = reservedOperationID else {
                throw error
            }
            return try await resolveMeltAfterAmbiguousFailure(
                wallet: wallet,
                quoteId: quoteId,
                mintURLString: mintURLString,
                operationID: operationID,
                fallbackQuote: storedMeltQuote
            )
        }

        let operationID = preparedMelt.operationId()
        AppLogger.wallet.info(
            "wallet-op melt prepared operation=\(WalletOperationCoordinator.privacySafeIdentifier(operationID), privacy: .public) quote=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public)"
        )

        do {
            AppLogger.wallet.info(
                "wallet-op native-call kind=melt phase=confirm operation=\(WalletOperationCoordinator.privacySafeIdentifier(operationID), privacy: .public) quote=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public)"
            )
            switch try await preparedMelt.confirmPreferAsync() {
            case .paid(let finalized):
                return settledMeltConfirmation(from: finalized, mintURLString: mintURLString)
            case .pending(let pendingMelt):
                // A lightning melt settles in seconds in the healthy case, so
                // stay in the lane and let CDK's `wait()` drive the saga to a
                // terminal state — it polls the mint internally; the app adds
                // no polling of its own. The old rule ("never run wait() after
                // leaving the repository lane") still holds: this wait runs
                // *inside* the lease, and the only wait that outlives it is
                // the post-cap residual, which is the sanctioned settlement
                // watcher. On-chain melts genuinely take minutes and keep the
                // immediate pending path.
                let method = storedMeltQuote?.paymentMethod
                if method == .bolt11 || method == .bolt12 {
                    switch await awaitMeltSettlementBounded(
                        cap: MeltSettlementWait.cap,
                        wait: { try await pendingMelt.wait() }
                    ) {
                    case .finalized(let finalized) where finalized.state == .paid || finalized.state == .issued:
                        AppLogger.wallet.info(
                            "wallet-op melt settled via wait operation=\(WalletOperationCoordinator.privacySafeIdentifier(operationID), privacy: .public)"
                        )
                        return settledMeltConfirmation(from: finalized, mintURLString: mintURLString)
                    case .finalized, .failed:
                        // A wait that ends any other way carries the same
                        // ambiguity as a thrown confirmation: resolve it
                        // against the mint through the recovery path.
                        return try await resolveMeltAfterAmbiguousFailure(
                            wallet: wallet,
                            quoteId: quoteId,
                            mintURLString: mintURLString,
                            operationID: operationID,
                            fallbackQuote: storedMeltQuote
                        )
                    case .capExpired(let residual):
                        AppLogger.wallet.info(
                            "wallet-op melt wait cap expired operation=\(WalletOperationCoordinator.privacySafeIdentifier(operationID), privacy: .public)"
                        )
                        return pendingMeltConfirmation(
                            storedMeltQuote: storedMeltQuote,
                            mintURLString: mintURLString,
                            deferredSettlement: residual
                        )
                    }
                }
                return pendingMeltConfirmation(
                    storedMeltQuote: storedMeltQuote,
                    mintURLString: mintURLString
                )
            }
        } catch {
            AppLogger.wallet.warning(
                "wallet-op melt confirmation returned error operation=\(WalletOperationCoordinator.privacySafeIdentifier(operationID), privacy: .public) quote=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return try await resolveMeltAfterAmbiguousFailure(
                wallet: wallet,
                quoteId: quoteId,
                mintURLString: mintURLString,
                operationID: operationID,
                fallbackQuote: storedMeltQuote
            )
        }
    }

    /// Resolve a post-reservation error through the mint/CDK recovery path. A
    /// paid or pending response becomes a normal result; a compensated response
    /// explicitly requires a fresh quote; an unknowable result is persisted by
    /// the manager and blocks immediate retry.
    private func resolveMeltAfterAmbiguousFailure(
        wallet: Wallet,
        quoteId: String,
        mintURLString: String,
        operationID: String,
        fallbackQuote: MeltQuote?
    ) async throws -> MeltConfirmation {
        let database = walletDatabase()
        await logMeltReservationState(
            wallet: wallet,
            database: database,
            quoteId: quoteId,
            operationID: operationID,
            stage: "before-resolution"
        )

        var checkedQuote: MeltQuote?
        do {
            checkedQuote = try await wallet.checkMeltQuoteStatus(quoteId: quoteId)
        } catch {
            // This is CDK's status-aware saga recovery, not an unconditional
            // reservation release. It may safely leave a still-pending saga in
            // place when the mint cannot establish a terminal outcome.
            let report = try? await wallet.recoverIncompleteSagas()
            AppLogger.wallet.info(
                "wallet-op melt recovery operation=\(WalletOperationCoordinator.privacySafeIdentifier(operationID), privacy: .public) recovered=\(report?.recovered ?? 0, privacy: .public) compensated=\(report?.compensated ?? 0, privacy: .public) skipped=\(report?.skipped ?? 0, privacy: .public) failed=\(report?.failed ?? 0, privacy: .public)"
            )
            checkedQuote = try? await wallet.checkMeltQuoteStatus(quoteId: quoteId)
        }

        await logMeltReservationState(
            wallet: wallet,
            database: database,
            quoteId: quoteId,
            operationID: operationID,
            stage: "after-resolution"
        )

        guard let checkedQuote else {
            throw MeltPaymentRecoveryError.unresolved(
                quoteID: quoteId,
                mintURL: mintURLString,
                operationID: operationID
            )
        }

        switch checkedQuote.state {
        case .paid, .issued:
            let transaction = try? await wallet.listTransactions(direction: .outgoing)
                .last(where: { $0.quoteId == quoteId })
            return MeltConfirmation(
                result: MeltPaymentResult(
                    preimage: transaction?.paymentProof ?? checkedQuote.paymentProof,
                    amount: transaction?.amount.value
                        ?? (checkedQuote.amount.value > 0 ? checkedQuote.amount.value : fallbackQuote?.amount.value ?? 0),
                    feePaid: transaction?.fee.value
                        ?? (checkedQuote.feeReserve.value > 0 ? checkedQuote.feeReserve.value : fallbackQuote?.feeReserve.value ?? 0),
                    mintUrl: mintURLString,
                    settlement: .settled
                )
            )
        case .pending:
            return MeltConfirmation(
                result: MeltPaymentResult(
                    preimage: nil,
                    amount: checkedQuote.amount.value > 0
                        ? checkedQuote.amount.value
                        : fallbackQuote?.amount.value ?? 0,
                    feePaid: checkedQuote.feeReserve.value > 0
                        ? checkedQuote.feeReserve.value
                        : fallbackQuote?.feeReserve.value ?? 0,
                    mintUrl: mintURLString,
                    settlement: .pending
                )
            )
        case .unpaid:
            guard let database else {
                throw MeltPaymentRecoveryError.unresolved(
                    quoteID: quoteId,
                    mintURL: mintURLString,
                    operationID: operationID
                )
            }

            do {
                let storedQuote = try await database.getMeltQuote(quoteId: quoteId)
                let saga = try await database.getSaga(id: operationID)
                let reservedProofs = try await database.getReservedProofs(operationId: operationID)
                guard saga == nil,
                      storedQuote?.usedByOperation == nil,
                      reservedProofs.isEmpty else {
                    throw MeltPaymentRecoveryError.unresolved(
                        quoteID: quoteId,
                        mintURL: mintURLString,
                        operationID: operationID
                    )
                }
            } catch let recoveryError as MeltPaymentRecoveryError {
                throw recoveryError
            } catch {
                // "Unpaid" only becomes definitely retryable after local
                // saga and quote-reservation reads both succeed and show that
                // compensation completed. An I/O error is not that evidence.
                throw MeltPaymentRecoveryError.unresolved(
                    quoteID: quoteId,
                    mintURL: mintURLString,
                    operationID: operationID
                )
            }
            throw MeltPaymentRecoveryError.compensated(operationID: operationID)
        }
    }

    private func logMeltReservationState(
        wallet: Wallet,
        database: WalletSqliteDatabase?,
        quoteId: String,
        operationID: String,
        stage: String
    ) async {
        var incompleteSagaCount = -1
        var sagaExists = false
        var reservedProofCount = -1
        var quoteReserved = false
        if let database {
            incompleteSagaCount = (try? await database.getIncompleteSagas().count) ?? -1
            sagaExists = ((try? await database.getSaga(id: operationID)) ?? nil) != nil
            reservedProofCount = (try? await database.getReservedProofs(operationId: operationID).count) ?? -1
            quoteReserved = (try? await database.getMeltQuote(quoteId: quoteId))?.usedByOperation != nil
        }
        let reservedBalance = (try? await wallet.totalReservedBalance().value) ?? UInt64.max
        let pendingSendCount = (try? await wallet.getPendingSends().count) ?? -1

        AppLogger.wallet.info(
            "wallet-op melt state stage=\(stage, privacy: .public) operation=\(WalletOperationCoordinator.privacySafeIdentifier(operationID), privacy: .public) incomplete_sagas=\(incompleteSagaCount, privacy: .public) saga_exists=\(sagaExists, privacy: .public) quote_reserved=\(quoteReserved, privacy: .public) reserved_proofs=\(reservedProofCount, privacy: .public) reserved_balance=\(reservedBalance, privacy: .public) pending_sends=\(pendingSendCount, privacy: .public)"
        )
    }

    private func mintQuoteInfo(
        from quote: MintQuote,
        fallbackAmount: UInt64?,
        paymentMethod: PaymentMethodKind
    ) -> MintQuoteInfo {
        let resolvedAmount = quote.amount?.value
            ?? (quote.amountPaid.value > 0 ? quote.amountPaid.value : nil)
            ?? fallbackAmount

        // Reusable BOLT12 offers (amountless or fixed) have no CDK creation field;
        // the amountless one is also reused across opens. Stamp the first time we
        // materialize each offer, then read it back so the "Created" row stays put.
        // Keyed by quote id, so a fixed offer minted from the Amount pencil gets
        // its own stable date.
        let createdAt: Date? = paymentMethod == .bolt12
            ? MintQuoteCreatedAtStore.recordIfAbsent(quoteId: quote.id, date: Date())
            : nil

        return MintQuoteInfo(
            id: quote.id,
            request: quote.request,
            amount: resolvedAmount,
            isAmountless: quote.amount == nil,
            paymentMethod: paymentMethod,
            state: mintQuoteState(from: quote, paymentMethod: paymentMethod),
            expiry: displayExpiry(quote.expiry),
            createdAt: createdAt,
            unit: PaymentRequestDecoder.unitDescription(quote.unit),
            mintURL: quote.mintUrl.url,
            amountPaid: quote.amountPaid.value,
            amountIssued: quote.amountIssued.value
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
        paymentMethod: PaymentMethodKind,
        fallbackMintUrl: String
    ) -> MeltQuoteInfo {
        MeltQuoteInfo(
            id: quote.id,
            mintUrl: quote.mintUrl?.url ?? fallbackMintUrl,
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
            try await replaceStoredMintQuote(quote, in: walletDatabase)
        } catch {
            AppLogger.wallet.error(
                "mint quote persistence failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(quote.id), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
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
            updatedAt: quote.updatedAt,
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
            updatedAt: max(quote.updatedAt, existingQuote.updatedAt),
            estimatedBlocks: quote.estimatedBlocks ?? existingQuote.estimatedBlocks,
            paymentMethod: paymentMethod,
            secretKey: quote.secretKey ?? existingQuote.secretKey,
            usedByOperation: quote.usedByOperation ?? existingQuote.usedByOperation,
            version: quote.version
        )
    }

    func replaceStoredMintQuote(
        _ quote: MintQuote,
        in walletDatabase: WalletSqliteDatabase
    ) async throws {
        // The FFI upsert accepts a stale record, including its reservation.
        // While the repository lease is held, reject stale app projections
        // instead of overwriting CDK's newer recovery state.
        if let current = try await walletDatabase.getMintQuote(quoteId: quote.id) {
            guard quote.version >= current.version,
                  quote.usedByOperation == current.usedByOperation else {
                throw WalletError.networkError("This receive request changed. Refresh it and try again.")
            }
        }
        try await walletDatabase.addMintQuote(quote: quote)
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

        try await replaceStoredMintQuote(refreshedQuote, in: walletDatabase)
        return refreshedQuote
    }

    private func createOnchainMintQuote(mintURL: String) async throws -> MintQuoteInfo {
        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let mintUrl = MintUrl(url: mintURL)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)

        let quote = try await wallet.mintQuote(
            paymentMethod: PaymentMethodKind.onchain.cdkMethod,
            amount: nil,
            description: nil,
            extra: "{}"
        )

        await persistMintQuote(quote, paymentMethod: .onchain)

        return mintQuoteInfo(from: quote, fallbackAmount: nil, paymentMethod: .onchain)
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

private enum LightningAddressResolver {
    static func resolveBolt11Invoice(address: String, amountMsat: UInt64) async throws -> String {
        let endpoint = try lightningAddressEndpoint(for: address)
        let payRequest = try await fetchJSON(LnurlPayRequest.self, from: endpoint)

        try throwIfServiceError(status: payRequest.status, reason: payRequest.reason)

        guard payRequest.tag == "payRequest" else {
            throw LightningAddressResolverError.invalidResponse("Lightning address did not return an LNURL-pay request.")
        }
        guard let callback = payRequest.callback,
              let minSendable = payRequest.minSendable,
              let maxSendable = payRequest.maxSendable else {
            throw LightningAddressResolverError.invalidResponse("Lightning address response is missing payment details.")
        }
        guard amountMsat >= minSendable, amountMsat <= maxSendable else {
            throw LightningAddressResolverError.amountOutOfRange(
                requestedMsat: amountMsat,
                minMsat: minSendable,
                maxMsat: maxSendable
            )
        }

        let callbackURL = try invoiceCallbackURL(callback: callback, amountMsat: amountMsat)
        let callbackResponse = try await fetchJSON(LnurlPayCallbackResponse.self, from: callbackURL)

        try throwIfServiceError(status: callbackResponse.status, reason: callbackResponse.reason)

        guard let paymentRequest = callbackResponse.pr?.trimmingCharacters(in: .whitespacesAndNewlines),
              !paymentRequest.isEmpty else {
            throw LightningAddressResolverError.missingInvoice
        }
        guard let metadata = await CdkRuntime.shared.lightningMetadata(from: paymentRequest),
              metadata.paymentMethod == .bolt11,
              metadata.amountMsat == amountMsat else {
            throw LightningAddressResolverError.invoiceMismatch
        }

        return metadata.normalizedRequest
    }

    private static func lightningAddressEndpoint(for address: String) throws -> URL {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty else {
            throw LightningAddressResolverError.invalidAddress
        }

        let username = String(parts[0])
        let domain = String(parts[1]).lowercased()
        guard domain.contains("."),
              !domain.hasPrefix("."),
              !domain.hasSuffix(".") else {
            throw LightningAddressResolverError.invalidAddress
        }

        guard let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) else {
            throw LightningAddressResolverError.invalidAddress
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.percentEncodedPath = "/.well-known/lnurlp/\(encodedUsername)"

        guard let url = components.url else {
            throw LightningAddressResolverError.invalidAddress
        }

        return url
    }

    private static func invoiceCallbackURL(callback: String, amountMsat: UInt64) throws -> URL {
        guard var components = URLComponents(string: callback),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false else {
            throw LightningAddressResolverError.invalidCallback
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name.lowercased() == "amount" }
        queryItems.append(URLQueryItem(name: "amount", value: String(amountMsat)))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw LightningAddressResolverError.invalidCallback
        }

        return url
    }

    private static func fetchJSON<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw LightningAddressResolverError.networkFailure
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LightningAddressResolverError.invalidResponse("Lightning address service returned an invalid JSON response.")
        }
    }

    private static func throwIfServiceError(status: String?, reason: String?) throws {
        guard status?.uppercased() == "ERROR" else { return }
        throw LightningAddressResolverError.serviceError(reason ?? "Lightning address service returned an error.")
    }

    private static var pathSegmentAllowed: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=%")
        return allowed
    }
}

private struct LnurlPayRequest: Decodable {
    let callback: String?
    let maxSendable: UInt64?
    let minSendable: UInt64?
    let metadata: String?
    let tag: String?
    let status: String?
    let reason: String?
}

private struct LnurlPayCallbackResponse: Decodable {
    let pr: String?
    let status: String?
    let reason: String?
}

private enum LightningAddressResolverError: LocalizedError {
    case invalidAddress
    case invalidCallback
    case invalidResponse(String)
    case serviceError(String)
    case networkFailure
    case amountOutOfRange(requestedMsat: UInt64, minMsat: UInt64, maxMsat: UInt64)
    case missingInvoice
    case invoiceMismatch

    /// True when the failure suggests the domain serves no LNURL-pay endpoint at all
    /// (e.g. HTTP 404 or a non-LNURL response), so the address may be a BIP-353 name.
    /// False for definitive LNURL-pay answers (service errors, amount limits, bad invoices),
    /// where falling back would mask the real error.
    var indicatesNoLnurlPayEndpoint: Bool {
        switch self {
        case .networkFailure, .invalidResponse:
            return true
        case .invalidAddress, .invalidCallback, .serviceError, .amountOutOfRange, .missingInvoice, .invoiceMismatch:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "That Lightning address does not look valid."
        case .invalidCallback:
            return "Lightning address service returned an invalid payment callback."
        case .invalidResponse(let message):
            return message
        case .serviceError(let reason):
            return reason
        case .networkFailure:
            return "Lightning address service could not be reached."
        case .amountOutOfRange(let requestedMsat, let minMsat, let maxMsat):
            return "Amount is outside this Lightning address range. Requested \(requestedMsat / 1000) sats, supported range is \(minMsat / 1000)-\(maxMsat / 1000) sats."
        case .missingInvoice:
            return "Lightning address service did not return an invoice."
        case .invoiceMismatch:
            return "Lightning address service returned an invoice for a different amount."
        }
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
