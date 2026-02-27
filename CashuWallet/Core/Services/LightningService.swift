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
    
    /// Create a melt quote for paying a Lightning invoice
    /// - Parameter invoice: The bolt11 invoice to pay
    /// - Returns: Melt quote with fee information
    func createMeltQuote(invoice: String) async throws -> MeltQuoteInfo {
        guard let repo = walletRepository(), let activeMint = getActiveMint() else {
            throw WalletError.notInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let mintUrl = try MintUrl(url: activeMint.url)
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .sat)
        
        let quote = try await wallet.meltQuote(
            method: PaymentMethod.bolt11,
            request: invoice,
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
