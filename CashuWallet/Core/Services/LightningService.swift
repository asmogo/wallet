import Foundation
import CashuDevKit

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
    private let getActiveMint: () -> MintInfo?
    
    // MARK: - Initialization
    
    init(
        walletRepository: @escaping () -> WalletRepository?,
        getActiveMint: @escaping () -> MintInfo?
    ) {
        self.walletRepository = walletRepository
        self.getActiveMint = getActiveMint
    }
    
    // MARK: - Minting (NUT-04) - Receive via Lightning
    
    /// Create a Lightning invoice to mint tokens
    /// - Parameter amount: Amount in satoshis
    /// - Returns: Mint quote with invoice details
    func createMintQuote(amount: UInt64) async throws -> MintQuoteInfo {
        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let mintUrl = try MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        
        let amountObj = Amount(value: amount)
        
        let quote = try await wallet.mintQuote(
            paymentMethod: PaymentMethod.bolt11,
            amount: amountObj,
            description: nil,
            extra: nil
        )
        
        return MintQuoteInfo(
            id: quote.id,
            request: quote.request,
            amount: amount,
            state: .pending,
            expiry: quote.expiry
        )
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
        
        let mintUrl = try MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let proofs = try await wallet.mint(
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
        
        let mintUrl = try MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        let parsedRequest = try LightningRequestParser.parse(request)
        
        let quote = try await wallet.meltQuote(
            method: parsedRequest.method,
            request: parsedRequest.request,
            options: nil,
            extra: nil
        )
        
        return MeltQuoteInfo(
            id: quote.id,
            amount: quote.amount.value,
            feeReserve: quote.feeReserve.value,
            state: .unpaid,
            expiry: quote.expiry
        )
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

        let mintUrl = try MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)

        let amountMsat = Amount(value: amount * 1000)
        let quote = try await wallet.meltHumanReadable(address: address, amountMsat: amountMsat)

        return MeltQuoteInfo(
            id: quote.id,
            amount: quote.amount.value,
            feeReserve: quote.feeReserve.value,
            state: .unpaid,
            expiry: quote.expiry
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
}
