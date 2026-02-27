import Foundation

// MARK: - Wallet Service Protocol

/// Protocol defining wallet operations.
/// This abstraction allows for different wallet implementations and facilitates testing.
protocol WalletServiceProtocol {
    /// Current total balance across all mints
    var balance: UInt64 { get async }
    
    /// Whether the wallet has been initialized
    var isInitialized: Bool { get }
    
    /// Initialize the wallet with a mnemonic
    func initialize(mnemonic: String) async throws
    
    /// Create a new wallet with a fresh mnemonic
    func createNewWallet() async throws -> String
    
    /// Restore wallet from mnemonic
    func restore(mnemonic: String) async throws
}

// MARK: - Mint Service Protocol

/// Protocol for mint management operations
protocol MintServiceProtocol {
    /// List of configured mints
    var mints: [MintInfo] { get async }
    
    /// Currently active mint
    var activeMint: MintInfo? { get async }
    
    /// Add a new mint
    func addMint(url: String) async throws -> MintInfo
    
    /// Remove a mint
    func removeMint(url: String) async throws
    
    /// Set the active mint
    func setActiveMint(_ mint: MintInfo) async throws
    
    /// Refresh mint info
    func refreshMintInfo(_ mint: MintInfo) async throws -> MintInfo
}

// MARK: - Token Service Protocol

/// Protocol for ecash token operations
protocol TokenServiceProtocol {
    /// Send tokens of specified amount
    func sendTokens(amount: UInt64, memo: String?) async throws -> SendTokenResult
    
    /// Receive/redeem a token
    func receiveToken(_ tokenString: String) async throws -> UInt64
    
    /// Parse token information without redeeming
    func parseToken(_ tokenString: String) throws -> TokenInfo
    
    /// Check if a token has been spent
    func checkTokenSpent(_ tokenString: String) async throws -> Bool
}

// MARK: - Transaction Service Protocol

/// Protocol for transaction history management
protocol TransactionServiceProtocol {
    /// All transactions
    var transactions: [WalletTransaction] { get async }
    
    /// Load transactions from storage
    func loadTransactions() async throws
    
    /// Add a new transaction
    func addTransaction(_ transaction: WalletTransaction) async throws
    
    /// Update transaction status
    func updateTransactionStatus(id: String, status: WalletTransaction.TransactionStatus) async throws
}

// MARK: - Quote Service Protocol

/// Protocol for Lightning quote operations (mint/melt)
protocol QuoteServiceProtocol {
    /// Create a mint quote (receive via Lightning)
    func createMintQuote(amount: UInt64) async throws -> MintQuoteInfo
    
    /// Check mint quote status
    func checkMintQuote(id: String) async throws -> MintQuoteInfo
    
    /// Mint tokens from a paid quote
    func mintTokens(quoteId: String) async throws -> UInt64
    
    /// Create a melt quote (pay via Lightning)
    func createMeltQuote(invoice: String) async throws -> MeltQuoteInfo
    
    /// Execute the melt (pay the invoice)
    func meltTokens(quoteId: String) async throws -> PaymentResult
}
