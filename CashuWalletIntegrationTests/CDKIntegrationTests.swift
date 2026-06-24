import XCTest

/// Integration tests for CDK-Swift library interactions
/// These test the CDK library itself, not UI interactions
class CDKIntegrationTests: XCTestCase {
    
    // MARK: - Setup
    
    override func setUpWithError() throws {
        // Initialize CDK logging
        let result = Cdk.initLogging(level: "debug")
        XCTAssertNotEqual(result, Cdk.FfiError.initializationError)
    }
    
    // MARK: - Wallet Repository Tests
    
    func testWalletRepositoryCreation() throws {
        let mnemonic = "test test test test test test test test test test test junk"
        let store = WalletStore.Sqlite(path: "/tmp/test-wallet.db")
        
        let repo = try WalletRepository(mnemonic: mnemonic, store: store)
        XCTAssertNotNil(repo)
    }
    
    // MARK: - Mint Integration Tests
    
    func testAddNutshellMint() async throws {
        let mnemonic = "test test test test test test test test test test test junk"
        let store = WalletStore.Sqlite(path: "/tmp/test-nutshell.db")
        let repo = try WalletRepository(mnemonic: mnemonic, store: store)
        
        let mintUrl = MintUrl(url: "http://localhost:3338")
        
        try await repo.createWallet(mintUrl: mintUrl, unit: .Sat, targetProofCount: nil)
        
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .Sat)
        XCTAssertNotNil(wallet)
    }
    
    func testAddCDKMint() async throws {
        let mnemonic = "test test test test test test test test test test test junk"
        let store = WalletStore.Sqlite(path: "/tmp/test-cdk.db")
        let repo = try WalletRepository(mnemonic: mnemonic, store: store)
        
        let mintUrl = MintUrl(url: "http://localhost:3339")
        
        try await repo.createWallet(mintUrl: mintUrl, unit: .Sat, targetProofCount: nil)
        
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .Sat)
        XCTAssertNotNil(wallet)
    }
    
    func testFetchMintInfo() async throws {
        let mnemonic = "test test test test test test test test test test test junk"
        let store = WalletStore.Sqlite(path: "/tmp/test-info.db")
        let repo = try WalletRepository(mnemonic: mnemonic, store: store)
        
        let mintUrl = MintUrl(url: "http://localhost:3338")
        try await repo.createWallet(mintUrl: mintUrl, unit: .Sat, targetProofCount: nil)
        
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .Sat)
        let info = try await wallet.getMintInfo()
        
        XCTAssertNotNil(info)
        XCTAssertFalse(info.name.isEmpty)
    }
    
    // MARK: - Minting Tests
    
    func testMintQuoteAndMintWithNutshell() async throws {
        let mnemonic = "test test test test test test test test test test test junk"
        let store = WalletStore.Sqlite(path: "/tmp/test-mint.db")
        let repo = try WalletRepository(mnemonic: mnemonic, store: store)
        
        let mintUrl = MintUrl(url: "http://localhost:3338")
        try await repo.createWallet(mintUrl: mintUrl, unit: .Sat, targetProofCount: nil)
        
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .Sat)
        
        // Create mint quote
        let quote = try await wallet.mintQuote(amount: 21, unit: .Sat, description: "Test invoice")
        XCTAssertNotNil(quote)
        XCTAssertFalse(quote.request.isEmpty)
        
        // Wait for payment (fake wallet pays instantly)
        var attempts = 0
        var currentState = try await wallet.checkMintQuote(quoteId: quote.id)
        while currentState.state != .Paid && attempts < 30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            currentState = try await wallet.checkMintQuote(quoteId: quote.id)
            attempts += 1
        }
        
        XCTAssertEqual(currentState.state, .Paid)
        
        // Mint tokens
        let proofs = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .None, spendingConditions: nil)
        XCTAssertNotEmpty(proofs)
    }
    
    func testMintQuoteAndMintWithCDK() async throws {
        let mnemonic = "test test test test test test test test test test test junk"
        let store = WalletStore.Sqlite(path: "/tmp/test-mint-cdk.db")
        let repo = try WalletRepository(mnemonic: mnemonic, store: store)
        
        let mintUrl = MintUrl(url: "http://localhost:3339")
        try await repo.createWallet(mintUrl: mintUrl, unit: .Sat, targetProofCount: nil)
        
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .Sat)
        
        // Create mint quote
        let quote = try await wallet.mintQuote(amount: 21, unit: .Sat, description: "Test invoice")
        XCTAssertNotNil(quote)
        XCTAssertFalse(quote.request.isEmpty)
        
        // Wait for payment (fake wallet pays instantly)
        var attempts = 0
        var currentState = try await wallet.checkMintQuote(quoteId: quote.id)
        while currentState.state != .Paid && attempts < 30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            currentState = try await wallet.checkMintQuote(quoteId: quote.id)
            attempts += 1
        }
        
        XCTAssertEqual(currentState.state, .Paid)
        
        // Mint tokens
        let proofs = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .None, spendingConditions: nil)
        XCTAssertNotEmpty(proofs)
    }
    
    // MARK: - Balance Tests
    
    func testBalanceAfterMinting() async throws {
        let mnemonic = "test test test test test test test test test test test junk"
        let store = WalletStore.Sqlite(path: "/tmp/test-balance.db")
        let repo = try WalletRepository(mnemonic: mnemonic, store: store)
        
        let mintUrl = MintUrl(url: "http://localhost:3338")
        try await repo.createWallet(mintUrl: mintUrl, unit: .Sat, targetProofCount: nil)
        
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .Sat)
        
        // Initial balance should be 0
        let initialBalance = try await wallet.totalBalance()
        XCTAssertEqual(initialBalance.amount, 0)
        
        // Mint some tokens
        let quote = try await wallet.mintQuote(amount: 100, unit: .Sat, description: "")
        
        var attempts = 0
        var currentState = try await wallet.checkMintQuote(quoteId: quote.id)
        while currentState.state != .Paid && attempts < 30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            currentState = try await wallet.checkMintQuote(quoteId: quote.id)
            attempts += 1
        }
        
        _ = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .None, spendingConditions: nil)
        
        // Check balance
        let finalBalance = try await wallet.totalBalance()
        XCTAssertEqual(finalBalance.amount, 100)
    }
    
    // MARK: - Token Operations
    
    func testSendToken() async throws {
        let mnemonic = "test test test test test test test test test test test junk"
        let store = WalletStore.Sqlite(path: "/tmp/test-send.db")
        let repo = try WalletRepository(mnemonic: mnemonic, store: store)
        
        let mintUrl = MintUrl(url: "http://localhost:3338")
        try await repo.createWallet(mintUrl: mintUrl, unit: .Sat, targetProofCount: nil)
        
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .Sat)
        
        // Mint tokens first
        let quote = try await wallet.mintQuote(amount: 50, unit: .Sat, description: "")
        
        var attempts = 0
        var currentState = try await wallet.checkMintQuote(quoteId: quote.id)
        while currentState.state != .Paid && attempts < 30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            currentState = try await wallet.checkMintQuote(quoteId: quote.id)
            attempts += 1
        }
        
        _ = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .None, spendingConditions: nil)
        
        // Send tokens
        let memo = "Test payment"
        let token = try await wallet.send(amount: 21, unit: .Sat, memo: memo, includeFees: false, spendingConditions: nil)
        
        XCTAssertNotNil(token)
        XCTAssertTrue(token.hasPrefix("cashu"))
    }
    
    func testReceiveToken() async throws {
        let mnemonic = "test test test test test test test test test test test junk"
        let store = WalletStore.Sqlite(path: "/tmp/test-receive.db")
        let repo = try WalletRepository(mnemonic: mnemonic, store: store)
        
        let mintUrl = MintUrl(url: "http://localhost:3338")
        try await repo.createWallet(mintUrl: mintUrl, unit: .Sat, targetProofCount: nil)
        
        let wallet = try await repo.getWallet(mintUrl: mintUrl, unit: .Sat)
        
        // Mint tokens
        let quote = try await wallet.mintQuote(amount: 50, unit: .Sat, description: "")
        
        var attempts = 0
        var currentState = try await wallet.checkMintQuote(quoteId: quote.id)
        while currentState.state != .Paid && attempts < 30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            currentState = try await wallet.checkMintQuote(quoteId: quote.id)
            attempts += 1
        }
        
        _ = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .None, spendingConditions: nil)
        
        // Send to get token string
        let tokenString = try await wallet.send(amount: 25, unit: .Sat, memo: "", includeFees: false, spendingConditions: nil)
        
        // Receive the token back
        let token = try Token(string: tokenString)
        let receivedAmount = try await wallet.receive(token: token, options: ReceiveOptions())
        
        XCTAssertGreaterThan(receivedAmount.amount, 0)
    }
}

extension XCTestCase {
    func XCTAssertNotEmpty<T: Collection>(_ collection: T, file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(collection.isEmpty, "Collection should not be empty", file: file, line: line)
    }
}
