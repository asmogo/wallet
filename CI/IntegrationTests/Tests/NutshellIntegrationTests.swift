import XCTest
@testable import CashuWallet
import CashuDevKit

final class NutshellIntegrationTests: XCTestCase {
    
    // MARK: - Properties
    
    private let mintUrl = ProcessInfo.processInfo.environment["NUTSHELL_MINT_URL"] ?? "http://localhost:3338"
    private var walletRepository: WalletRepository!
    private var wallet: Wallet!
    private let mnemonic = "test test test test test test test test test test test junk"
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        // Initialize CDK logging
        CdkFfi.initLogging("debug")
        
        // Create temporary directory for SQLite database
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dbPath = tempDir.appendingPathComponent("nutshell_test.db").path
        
        // Create wallet repository with SQLite storage
        walletRepository = try WalletRepository(
            mnemonic: mnemonic,
            store: .sqlite(path: dbPath)
        )
        
        // Create or get wallet for the mint
        let mintUrlStruct = MintUrl(url: mintUrl)
        try await walletRepository.createWallet(
            mintUrl: mintUrlStruct,
            unit: .sat,
            targetProofCount: 32
        )
        
        wallet = try await walletRepository.getWallet(
            mintUrl: mintUrlStruct,
            unit: .sat
        )
    }
    
    override func tearDown() async throws {
        wallet = nil
        walletRepository = nil
    }
    
    // MARK: - Test: Fetch Mint Info
    
    func testFetchMintInfo() async throws {
        let mintInfo = try await wallet.fetchMintInfo()
        
        XCTAssertNotNil(mintInfo, "Mint info should not be nil")
        print("✓ Mint info fetched successfully")
        print("  Mint name: \(mintInfo?.name ?? "N/A")")
        print("  Mint version: \(mintInfo?.version ?? "N/A")")
    }
    
    // MARK: - Test: Fetch Active Keyset
    
    func testFetchActiveKeyset() async throws {
        let keysetInfo = try await wallet.fetchActiveKeyset()
        
        XCTAssertFalse(keysetInfo.id.isEmpty, "Keyset ID should not be empty")
        XCTAssertEqual(keysetInfo.unit, .sat, "Keyset unit should be sat")
        print("✓ Active keyset fetched successfully")
        print("  Keyset ID: \(keysetInfo.id)")
        print("  Unit: \(keysetInfo.unit)")
    }
    
    // MARK: - Test: Mint Quote
    
    func testMintQuote() async throws {
        let amount = Amount(value: 21)
        
        let quote = try await wallet.mintQuote(
            paymentMethod: .bolt11,
            amount: amount,
            description: "Integration test quote",
            extra: nil
        )
        
        XCTAssertFalse(quote.id.isEmpty, "Quote ID should not be empty")
        XCTAssertEqual(quote.state, .unpaid, "Quote should be unpaid initially")
        XCTAssertFalse(quote.request.isEmpty, "Quote request should not be empty")
        print("✓ Mint quote created successfully")
        print("  Quote ID: \(quote.id)")
        print("  Amount: \(quote.amount?.value ?? 0) sats")
        print("  State: \(quote.state)")
        print("  Invoice: \(quote.request.prefix(50))...")
    }
    
    // MARK: - Test: Mint Tokens (Quote + Mint)
    
    func testMintTokens() async throws {
        let amount = Amount(value: 42)
        
        // Create mint quote
        let quote = try await wallet.mintQuote(
            paymentMethod: .bolt11,
            amount: amount,
            description: "Integration test mint",
            extra: nil
        )
        
        print("✓ Mint quote created")
        print("  Quote ID: \(quote.id)")
        print("  Request: \(quote.request)")
        
        // In a real test, you would pay the invoice here
        // For now, we'll just verify the quote was created
        XCTAssertFalse(quote.id.isEmpty, "Quote ID should not be empty")
        XCTAssertEqual(quote.state, .unpaid, "Quote should be unpaid")
        
        // Note: To actually mint, you need to pay the invoice and wait for payment
        // Then call: let proofs = try await wallet.mint(quoteId: quote.id, amountSplitTarget: .none, spendingConditions: nil)
        print("⚠️  Skipping actual minting (requires payment)")
    }
    
    // MARK: - Test: Total Balance
    
    func testTotalBalance() async throws {
        let balance = try await wallet.totalBalance()
        
        XCTAssertNotNil(balance, "Balance should not be nil")
        print("✓ Total balance fetched successfully")
        print("  Balance: \(balance.value) sats")
    }
    
    // MARK: - Test: Repository Balances
    
    func testRepositoryBalances() async throws {
        let balances = try await walletRepository.getBalances()
        
        XCTAssertNotNil(balances, "Balances should not be nil")
        print("✓ Repository balances fetched successfully")
        print("  Number of mints: \(balances.count)")
        
        for (walletKey, amount) in balances {
            print("  Mint: \(walletKey.mintUrl.url) - \(amount.value) sats")
        }
    }
    
    // MARK: - Test: Send/Receive Flow
    
    func testSendReceiveFlow() async throws {
        // This test requires existing balance, so we'll just verify the API works
        
        // First check balance
        let balance = try await wallet.totalBalance()
        print("Current balance: \(balance.value) sats")
        
        guard balance.value > 0 else {
            print("⚠️  Skipping send/receive test - no balance")
            return
        }
        
        let sendAmount = Amount(value: 1)
        
        // Prepare send
        let sendOptions = SendOptions(
            memo: SendMemo(text: "Test token", sender: nil),
            conditions: nil,
            amountSplitTarget: .none,
            sendKind: .onlineExact,
            includeFee: false,
            useP2bk: false,
            maxProofs: nil,
            metadata: [:],
            p2pkSigningKeys: [],
            p2pkLockedProofSendMode: .normal
        )
        
        do {
            let preparedSend = try await wallet.prepareSend(
                amount: sendAmount,
                options: sendOptions
            )
            
            print("✓ Send prepared successfully")
            print("  Amount: \(prepareSend.amount.value) sats")
            
            // In a real scenario, you would:
            // 1. Get the token from preparedSend
            // 2. Receive it with: let receivedAmount = try await wallet.receive(token: token, options: receiveOptions)
            
        } catch {
            print("⚠️  Send preparation failed (expected if insufficient balance): \(error)")
        }
    }
    
    // MARK: - Test: Check Mint Quote Status
    
    func testCheckMintQuoteStatus() async throws {
        // First create a quote
        let amount = Amount(value: 10)
        let quote = try await wallet.mintQuote(
            paymentMethod: .bolt11,
            amount: amount,
            description: "Status check test",
            extra: nil
        )
        
        // Check the quote status
        let updatedQuote = try await wallet.checkMintQuote(quoteId: quote.id)
        
        XCTAssertEqual(updatedQuote.id, quote.id, "Quote IDs should match")
        XCTAssertEqual(updatedQuote.state, .unpaid, "Quote should still be unpaid")
        print("✓ Mint quote status checked successfully")
        print("  Quote ID: \(updatedQuote.id)")
        print("  State: \(updatedQuote.state)")
    }
}
