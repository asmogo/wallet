import Foundation
import CashuDevKit
import P256K
import Security

// MARK: - Lightning Service

/// Service responsible for Lightning Network operations (NUT-04/NUT-05).
/// Handles minting (receiving via Lightning) and melting (paying via Lightning).
@MainActor
class LightningService: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether an operation is in progress
    @Published var isLoading = false
    
    // MARK: - Dependencies
    
    private let walletRepository: () -> WalletRepository?
    private let walletDatabase: () -> WalletSqliteDatabase?
    private let getActiveMint: () -> MintInfo?
    
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
            guard let walletDatabase = walletDatabase(), let amount else {
                throw WalletError.notInitialized
            }
            return try await createOnchainMintQuote(
                amount: amount,
                activeMint: activeMint,
                walletDatabase: walletDatabase
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
        
        return mintQuoteInfo(from: quote, fallbackAmount: amount, paymentMethod: method)
    }

    func checkMintQuote(quoteId: String) async throws -> MintQuoteInfo {
        guard let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }

        if let walletDatabase = walletDatabase(),
           let existingQuote = try await walletDatabase.getMintQuote(quoteId: quoteId),
           PaymentMethodKind.from(existingQuote.paymentMethod) == .onchain {
            return try await checkOnchainMintQuote(
                quoteId: quoteId,
                activeMint: activeMint,
                walletDatabase: walletDatabase,
                existingQuote: existingQuote
            )
        }

        guard let repo = walletRepository() else {
            throw WalletError.notInitialized
        }

        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let quote = try await wallet.checkMintQuote(quoteId: quoteId)
        let paymentMethod = PaymentMethodKind.from(quote.paymentMethod) ?? .bolt11
        return mintQuoteInfo(from: quote, fallbackAmount: nil, paymentMethod: paymentMethod)
    }
    
    /// Mint tokens after invoice is paid
    /// - Parameter quoteId: The quote ID to mint
    /// - Returns: Total amount minted
    func mintTokens(quoteId: String) async throws -> UInt64 {
        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let proofs = try await wallet.mintUnified(
            quoteId: quoteId,
            amountSplitTarget: SplitTarget.none,
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
        let parsedRequest = try parseMeltRequest(request)

        if parsedRequest.paymentMethod == .onchain {
            throw WalletError.networkError("On-chain payments require an amount before requesting a quote.")
        }
        
        let quote = try await wallet.meltQuote(
            method: parsedRequest.method,
            request: parsedRequest.request,
            options: nil,
            extra: nil
        )

        return meltQuoteInfo(from: quote, paymentMethod: parsedRequest.paymentMethod)
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
        let quote = try await wallet.meltHumanReadable(address: address, amountMsat: amountMsat)

        return meltQuoteInfo(from: quote, paymentMethod: .bolt11)
    }

    func createOnchainMeltQuote(address: String, amount: UInt64) async throws -> MeltQuoteInfo {
        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        let mintUrl = MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let normalizedAddress = PaymentRequestParser.normalizeBitcoinRequest(address)
        let quote = try await wallet.meltQuote(
            method: PaymentMethodKind.onchain.cdkMethod,
            request: normalizedAddress,
            options: .amountless(amountMsat: Amount(value: amount * 1000)),
            extra: nil
        )

        return meltQuoteInfo(from: quote, paymentMethod: .onchain)
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
    
    // MARK: - Payment Request Parsing
    
    private struct ParsedMeltRequest {
        let request: String
        let method: PaymentMethod
        let paymentMethod: PaymentMethodKind
    }
    
    private func parseMeltRequest(_ request: String) throws -> ParsedMeltRequest {
        if PaymentRequestParser.isBitcoinAddress(request) {
            return ParsedMeltRequest(
                request: PaymentRequestParser.normalizeBitcoinRequest(request),
                method: PaymentMethodKind.onchain.cdkMethod,
                paymentMethod: .onchain
            )
        }

        let normalizedRequest = PaymentRequestParser.normalizeLightningRequest(request)
        let decodedRequest = try decodeInvoice(invoiceStr: normalizedRequest)
        
        let paymentMethod: PaymentMethodKind
        switch decodedRequest.paymentType {
        case .bolt11:
            paymentMethod = .bolt11
        case .bolt12:
            paymentMethod = .bolt12
        }
        
        return ParsedMeltRequest(
            request: normalizedRequest,
            method: paymentMethod.cdkMethod,
            paymentMethod: paymentMethod
        )
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
        
        let mintUrl = try MintUrl(url: activeMint.url)
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
            state: MintQuoteState(quote.state),
            expiry: quote.expiry
        )
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
            expiry: quote.expiry
        )
    }

    private func createOnchainMintQuote(
        amount: UInt64,
        activeMint: MintInfo,
        walletDatabase: WalletSqliteDatabase
    ) async throws -> MintQuoteInfo {
        let quoteKeypair = try generateMintQuoteKeypair()
        let requestBody = OnchainMintQuoteRequestBody(amount: amount, pubkey: quoteKeypair.pubkey)
        let response: OnchainMintQuoteResponse = try await performOnchainRequest(
            url: try onchainMintQuoteURL(for: activeMint.url),
            method: "POST",
            body: try JSONEncoder().encode(requestBody)
        )

        let storedQuote = makeStoredOnchainMintQuote(
            response: response,
            activeMint: activeMint,
            secretKeyHex: quoteKeypair.secretKeyHex,
            amount: amount,
            usedByOperation: nil,
            version: 0
        )
        try await walletDatabase.addMintQuote(quote: storedQuote)

        return MintQuoteInfo(
            id: response.quote,
            request: response.request,
            amount: amount,
            paymentMethod: .onchain,
            state: MintQuoteState(onchainQuoteState(from: response)),
            expiry: normalizedExpiry(response.expiry)
        )
    }

    private func checkOnchainMintQuote(
        quoteId: String,
        activeMint: MintInfo,
        walletDatabase: WalletSqliteDatabase,
        existingQuote: MintQuote
    ) async throws -> MintQuoteInfo {
        let response: OnchainMintQuoteResponse = try await performOnchainRequest(
            url: try onchainMintQuoteURL(for: activeMint.url, quoteId: quoteId),
            method: "GET"
        )

        let updatedQuote = makeStoredOnchainMintQuote(
            response: response,
            activeMint: activeMint,
            secretKeyHex: existingQuote.secretKey,
            amount: existingQuote.amount?.value ?? response.amountPaid
                ?? response.amountIssued,
            usedByOperation: existingQuote.usedByOperation,
            version: existingQuote.version
        )
        try await walletDatabase.addMintQuote(quote: updatedQuote)

        return MintQuoteInfo(
            id: response.quote,
            request: response.request,
            amount: updatedQuote.amount?.value,
            paymentMethod: .onchain,
            state: MintQuoteState(updatedQuote.state),
            expiry: normalizedExpiry(response.expiry)
        )
    }

    private func performOnchainRequest<Response: Decodable>(
        url: URL,
        method: String,
        body: Data? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalletError.networkError("Mint returned a non-HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OnchainMintErrorResponse.self, from: data)
            let detail = apiError?.detail ?? String(data: data, encoding: .utf8) ?? "Unknown mint error."
            throw WalletError.networkError(detail)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            throw WalletError.networkError("Failed to decode on-chain mint quote response: \(responseBody)")
        }
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

    private func makeStoredOnchainMintQuote(
        response: OnchainMintQuoteResponse,
        activeMint: MintInfo,
        secretKeyHex: String?,
        amount: UInt64?,
        usedByOperation: String?,
        version: UInt32
    ) -> MintQuote {
        MintQuote(
            id: response.quote,
            amount: amount.map(Amount.init(value:)),
            unit: .sat,
            request: response.request,
            state: onchainQuoteState(from: response),
            expiry: response.expiry ?? 0,
            mintUrl: MintUrl(url: activeMint.url),
            amountIssued: Amount(value: response.amountIssued ?? 0),
            amountPaid: Amount(value: response.amountPaid ?? 0),
            paymentMethod: PaymentMethodKind.onchain.cdkMethod,
            secretKey: secretKeyHex,
            usedByOperation: usedByOperation,
            version: version
        )
    }

    private func onchainQuoteState(from response: OnchainMintQuoteResponse) -> QuoteState {
        if (response.amountIssued ?? 0) > 0 {
            return .issued
        }
        if (response.amountPaid ?? 0) > 0 {
            return .paid
        }
        return .unpaid
    }

    private func normalizedExpiry(_ expiry: UInt64?) -> UInt64? {
        guard let expiry, expiry > 0 else {
            return nil
        }
        return expiry
    }

    private func generateMintQuoteKeypair() throws -> MintQuoteKeypair {
        let privateKeyBytes = try generateRandomPrivateKeyBytes()
        let privateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKeyBytes)
        let secretKeyHex = privateKey.dataRepresentation.map { String(format: "%02x", $0) }.joined()
        let publicKeyHex = privateKey.xonly.bytes.map { String(format: "%02x", $0) }.joined()
        return MintQuoteKeypair(secretKeyHex: secretKeyHex, pubkey: "02\(publicKeyHex)")
    }

    private func generateRandomPrivateKeyBytes() throws -> [UInt8] {
        for _ in 0..<10 {
            var randomBytes = [UInt8](repeating: 0, count: 32)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)

            guard status == errSecSuccess else {
                throw WalletError.networkError("Failed to generate a secure quote key.")
            }

            if (try? P256K.Schnorr.PrivateKey(dataRepresentation: randomBytes)) != nil {
                return randomBytes
            }
        }

        throw WalletError.networkError("Failed to generate a valid quote key.")
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

private struct MintQuoteKeypair {
    let secretKeyHex: String
    let pubkey: String
}

private struct OnchainMintQuoteRequestBody: Encodable {
    let amount: UInt64
    let unit = "sat"
    let description: String? = nil
    let pubkey: String
}

private struct OnchainMintQuoteResponse: Decodable {
    let quote: String
    let request: String
    let expiry: UInt64?
    let amountPaid: UInt64?
    let amountIssued: UInt64?

    enum CodingKeys: String, CodingKey {
        case quote
        case request
        case expiry
        case amountPaid = "amount_paid"
        case amountIssued = "amount_issued"
    }
}

private struct OnchainMintErrorResponse: Decodable {
    let detail: String?
}
