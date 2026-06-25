// NutshellIntegrationTests.swift
//
// Integration tests against a live Nutshell mint running the FakeWallet
// backend (auto-pays bolt11 quotes). Exercises the cdk-swift wallet API
// end-to-end: discovery, minting, send/receive, and quote state.
//
// Requires a running mint via `CI/setup-nutshell.sh` + `CI/start-nutshell.sh`.

import XCTest
import Cdk

final class NutshellIntegrationTests: IntegrationTestBase {
    override var mintUrlStr: String {
        ProcessInfo.processInfo.environment["NUTSHELL_MINT_URL"] ?? "http://localhost:3338"
    }

    override var dbNamePrefix: String { "nutshell_test" }

    // MARK: - Discovery

    func testFetchMintInfo() async throws {
        let info = try await wallet.fetchMintInfo()
        XCTAssertNotNil(info, "Nutshell mint should return mint info")
        XCTAssertFalse(info?.name?.isEmpty ?? true, "Mint name should not be empty")
    }

    func testGetMintKeysets() async throws {
        let keysets = try await wallet.getMintKeysets(filter: .active)
        XCTAssertFalse(keysets.isEmpty, "Nutshell mint should have at least one active keyset")
        for keyset in keysets {
            XCTAssertEqual(keyset.unit, .sat, "Keyset unit should be sat")
        }
    }

    // MARK: - Minting

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

    // MARK: - Send

    func testPrepareAndConfirmSend() async throws {
        _ = try await mintSats(50)

        let prepared = try await wallet.prepareSend(
            amount: Amount(value: 21),
            options: SendOptions(
                memo: SendMemo(memo: "Nutshell test send", includeMemo: true),
                conditions: nil,
                amountSplitTarget: .none,
                sendKind: .onlineExact,
                includeFee: false,
                useP2bk: false,
                maxProofs: nil,
                metadata: [:],
                p2pkSigningKeys: [],
                p2pkLockedProofSendMode: .swap
            )
        )

        XCTAssertEqual(prepared.amount().value, 21, "Prepared amount should match requested")
        XCTAssertTrue(prepared.proofs().count > 0, "Should have proofs")

        let token = try await prepared.confirm(memo: "Test receive")
        let tokenString = token.encode()
        XCTAssertTrue(tokenString.hasPrefix("cashu"), "Token should start with cashu prefix")

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
                useP2bk: false,
                maxProofs: nil,
                metadata: [:],
                p2pkSigningKeys: [],
                p2pkLockedProofSendMode: .swap
            )
        )

        try await prepared.cancel()

        let balance = try await wallet.totalBalance()
        XCTAssertEqual(balance.value, 50, "Balance should remain 50 after cancel")
    }

    // MARK: - Receive

    func testReceiveTokenFromAnotherWallet() async throws {
        let senderDbPath = NSTemporaryDirectory().appending("nutshell_sender_\(UUID().uuidString).sqlite")
        let senderRepo = try WalletRepository(
            mnemonic: try generateMnemonic(),
            store: .sqlite(path: senderDbPath)
        )

        let senderMintUrl = MintUrl(url: mintUrlStr)
        try await senderRepo.createWallet(mintUrl: senderMintUrl, unit: .sat, targetProofCount: nil)
        let senderWallet = try await senderRepo.getWallet(mintUrl: senderMintUrl, unit: .sat)

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
                useP2bk: false,
                maxProofs: nil,
                metadata: [:],
                p2pkSigningKeys: [],
                p2pkLockedProofSendMode: .swap
            )
        )

        let token = try await prepared.confirm(memo: nil)
        let tokenString = token.encode()

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

        try? FileManager.default.removeItem(atPath: senderDbPath)
    }

    // MARK: - Negative paths

    func testSendMoreThanBalanceThrows() async throws {
        _ = try await mintSats(10)

        do {
            _ = try await wallet.prepareSend(
                amount: Amount(value: 999),
                options: SendOptions(
                    memo: nil,
                    conditions: nil,
                    amountSplitTarget: .none,
                    sendKind: .onlineExact,
                    includeFee: false,
                    useP2bk: false,
                    maxProofs: nil,
                    metadata: [:],
                    p2pkSigningKeys: [],
                    p2pkLockedProofSendMode: .swap
                )
            )
            XCTFail("Expected an error when sending more than balance")
        } catch {
            // Any error is correct — the mint / CDK should reject insufficient funds.
            let balance = try await wallet.totalBalance()
            XCTAssertEqual(balance.value, 10, "Balance must not change after a failed send")
        }
    }

    func testReceiveSameTokenTwiceFailsSecondTime() async throws {
        // Mint proofs, build a token, receive it once, then attempt a second receive.
        _ = try await mintSats(30)

        let prepared = try await wallet.prepareSend(
            amount: Amount(value: 10),
            options: SendOptions(
                memo: nil,
                conditions: nil,
                amountSplitTarget: .none,
                sendKind: .onlineExact,
                includeFee: false,
                useP2bk: false,
                maxProofs: nil,
                metadata: [:],
                p2pkSigningKeys: [],
                p2pkLockedProofSendMode: .swap
            )
        )
        let token = try await prepared.confirm(memo: nil)
        let tokenString = token.encode()

        // First receive — should succeed.
        let receiverDbPath = NSTemporaryDirectory()
            .appending("receiver_\(UUID().uuidString).sqlite")
        let receiverRepo = try WalletRepository(
            mnemonic: try generateMnemonic(),
            store: .sqlite(path: receiverDbPath)
        )
        let mintUrl = MintUrl(url: mintUrlStr)
        try await receiverRepo.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)
        let receiverWallet = try await receiverRepo.getWallet(mintUrl: mintUrl, unit: .sat)
        let decoded = try Token.decode(encodedToken: tokenString)
        let opts = ReceiveOptions(
            amountSplitTarget: .none, p2pkSigningKeys: [],
            preimages: [], metadata: [:]
        )
        let received = try await receiverWallet.receive(token: decoded, options: opts)
        XCTAssertEqual(received.value, 10, "First receive should succeed")

        // Second receive of the same token — mint must reject it.
        do {
            let decoded2 = try Token.decode(encodedToken: tokenString)
            _ = try await receiverWallet.receive(token: decoded2, options: opts)
            XCTFail("Double-spend should have been rejected by the mint")
        } catch {
            // Expected: "Token is already spent" or equivalent CDK error.
        }

        try? FileManager.default.removeItem(atPath: receiverDbPath)
    }

    func testMintQuoteBalanceZeroWithoutPayment() async throws {
        let quote = try await wallet.mintQuote(
            paymentMethod: .bolt11,
            amount: Amount(value: 50),
            description: "Unpaid quote test",
            extra: nil
        )
        XCTAssertEqual(quote.state, .unpaid, "Fresh quote must be unpaid")

        let balance = try await wallet.totalBalance()
        XCTAssertEqual(balance.value, 0, "Balance must remain 0 before payment")
    }

    // MARK: - Quote State

    func testMintQuoteStateTransitions() async throws {
        let quote = try await wallet.mintQuote(
            paymentMethod: .bolt11,
            amount: Amount(value: 42),
            description: "State transition test",
            extra: nil
        )

        XCTAssertEqual(quote.state, .unpaid, "Initial state should be unpaid")

        let proofs = try await mintSats(42)
        XCTAssertFalse(proofs.isEmpty, "Should have minted proofs")

        let paidQuote = try await wallet.checkMintQuote(quoteId: quote.id)
        XCTAssertEqual(paidQuote.state, .paid, "Quote should be paid after minting")
    }
}
