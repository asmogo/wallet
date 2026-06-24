// CDKIntegrationTests.swift
//
// Integration tests for the cashuCDK mint implementation.
// Tests the CDK-Swift library against a real CDK mint running with fake wallet.

import XCTest
import Cdk

final class CDKIntegrationTests: IntegrationTestBase {
    override var mintUrlStr: String {
        ProcessInfo.processInfo.environment["CDK_MINT_URL"] ?? "http://localhost:3339"
    }

    override var dbNamePrefix: String { "cdk_test" }

    // MARK: - Discovery Tests

    func testFetchMintInfo() async throws {
        let info = try await wallet.fetchMintInfo()
        XCTAssertNotNil(info, "CDK mint should return mint info")
        XCTAssertFalse(info?.name.isEmpty ?? true, "Mint name should not be empty")
    }

    func testGetMintKeysets() async throws {
        let keysets = try await wallet.getMintKeysets(filter: .active)
        XCTAssertFalse(keysets.isEmpty, "CDK mint should have at least one active keyset")
        for keyset in keysets {
            XCTAssertEqual(keyset.unit, .sat, "Keyset unit should be sat")
        }
    }

    // MARK: - Minting Tests

    func testBalanceAfterMinting() async throws {
        let initialBalance = try await wallet.totalBalance()
        XCTAssertEqual(initialBalance.value, 0, "Initial balance should be 0")
        _ = try await mintSats(100)
        let finalBalance = try await wallet.totalBalance()
        XCTAssertEqual(finalBalance.value, 100, "Balance should be 100 after minting")
    }

    func testMultipleTokensMinting() async throws {
        let batch1 = try await mintSats(21)
        let batch2 = try await mintSats(42)
        
        let total1 = batch1.reduce(UInt64(0)) { $0 + $1.amount.value }
        let total2 = batch2.reduce(UInt64(0)) { $0 + $1.amount.value }
        
        XCTAssertEqual(total1, 21, "First batch should equal 21 sats")
        XCTAssertEqual(total2, 42, "Second batch should equal 42 sats")
        
        let balance = try await wallet.totalBalance()
        XCTAssertEqual(balance.value, 63, "Balance should be 63 after minting 21 + 42")
    }

    // MARK: - Send Tests

    func testPrepareAndConfirmSend() async throws {
        _ = try await mintSats(50)
        
        let prepared = try await wallet.prepareSend(
            amount: Amount(value: 21),
            options: SendOptions(
                memo: SendMemo(memo: "CDK test send", includeMemo: true),
                conditions: nil,
                amountSplitTarget: .none,
                sendKind: .onlineExact,
                includeFee: false,
                useP2pk: false,
                maxProofs: nil,
                metadata: [:],
                signingKeys: [],
                p2pkLockedProofSendMode: .swap
            )
        )
        
        XCTAssertEqual(prepared.amount.value, 21, "Prepared amount should match requested")
        XCTAssertTrue(prepared.proofs.count > 0, "Should have proofs")
        
        // Confirm the send and get token
        let token = try await prepared.confirm(memo: "Test receive")
        let tokenString = token.encode()
        
        XCTAssertTrue(tokenString.hasPrefix("cashu"), "Token should start with cashu prefix")
        
        // Check balance decreased
        let balance = try await wallet.totalBalance()
        XCTAssertEqual(balance.value, 29, "Balance should be 29 after sending 21")
    }

    func testCancelSendKeepsBalance() async throws {
        _ = try await mintSats(50)
        
        let prepared = try await wallet.prepareSend(
            amount: Amount(value: 20),
            options: SendOptions(
                memo: nil,
                conditions: nil,
                amountSplitTarget: .none,
                sendKind: .onlineExact,
                includeFee: false,
                useP2pk: false,
                maxProofs: nil,
                metadata: [:],
                signingKeys: [],
                p2pkLockedProofSendMode: .swap
            )
        )
        
        try await prepared.cancel()
        
        let balance = try await wallet.totalBalance()
        XCTAssertEqual(balance.value, 50, "Balance should remain 50 after cancel")
    }

    // MARK: - Receive Tests

    func testReceiveTokenFromAnotherWallet() async throws {
        // Create a separate sender wallet
        let senderDbPath = NSTemporaryDirectory().appending("cdk_sender_\(UUID().uuidString).sqlite")
        let senderRepo = try WalletRepository(
            mnemonic: testMnemonic,
            store: .sqlite(path: senderDbPath)
        )
        
        let senderMintUrl = MintUrl(url: mintUrlStr)
        try await senderRepo.createWallet(mintUrl: senderMintUrl, unit: .sat, targetProofCount: nil)
        let senderWallet = try await senderRepo.getWallet(mintUrl: senderMintUrl, unit: .sat)
        
        // Sender mints and sends
        let senderProofs = try await mintSats(80, wallet: senderWallet)
        XCTAssertFalse(senderProofs.isEmpty, "Sender should have minted proofs")
        
        let prepared = try await senderWallet.prepareSend(
            amount: Amount(value: 30),
            options: SendOptions(
                memo: SendMemo(memo: "Test cross-wallet receive", includeMemo: true),
                conditions: nil,
                amountSplitTarget: .none,
                sendKind: .onlineExact,
                includeFee: false,
                useP2pk: false,
                maxProofs: nil,
                metadata: [:],
                signingKeys: [],
                p2pkLockedProofSendMode: .swap
            )
        )
        
        let token = try await prepared.confirm(memo: nil)
        let tokenString = token.encode()
        
        // Receiver (main wallet) receives the token
        let decodedToken = try Token.decode(encodedToken: tokenString)
        let receivedAmount = try await wallet.receive(
            token: decodedToken,
            options: ReceiveOptions(
                amountSplitTarget: .none,
                p2pkSigningKeys: [],
                preimages: [],
                metadata: [:]
            )
        )
        
        XCTAssertEqual(receivedAmount.value, 30, "Should receive 30 sats")
        
        // Clean up sender repo files
        try? FileManager.default.removeItem(atPath: senderDbPath)
    }

    // MARK: - Quote State Tests

    func testMintQuoteStateTransitions() async throws {
        let quote = try await wallet.mintQuote(
            paymentMethod: .bolt11,
            amount: Amount(value: 42),
            description: "State transition test",
            extra: nil
        )
        
        XCTAssertEqual(quote.state, .unpaid, "Initial state should be unpaid")
        
        // Wait for auto-payment and mint
        let proofs = try await mintSats(42)
        XCTAssertFalse(proofs.isEmpty, "Should have minted proofs")
        
        let paidQuote = try await wallet.checkMintQuote(quoteId: quote.id)
        XCTAssertEqual(paidQuote.state, .paid, "Quote should be paid after minting")
    }

    // MARK: - Helper Methods

    private func mintSats(_ amount: UInt64, wallet: Wallet? = nil) async throws -> [Proof] {
        let targetWallet = wallet ?? self.wallet
        
        let quote = try await targetWallet.mintQuote(
            paymentMethod: .bolt11,
            amount: Amount(value: amount),
            description: "E2E mint test",
            extra: nil
        )
        
        // Poll until paid
        var currentState = quote.state
        let timeout = Date().addingTimeInterval(15.0)
        while currentState != .paid && Date() < timeout {
            try await Task.sleep(nanoseconds: 200_000_000)
            let updated = try await targetWallet.checkMintQuote(quoteId: quote.id)
            currentState = updated.state
        }
        
        guard currentState == .paid else {
            throw NSError(domain: "IntegrationTest", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Mint quote did not reach paid state"
            ])
        }
        
        let proofs = try await targetWallet.mint(
            quoteId: quote.id,
            amountSplitTarget: .none,
            spendingConditions: nil
        )
        
        XCTAssertFalse(proofs.isEmpty, "Should have minted at least one proof")
        return proofs
    }
}
