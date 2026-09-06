// NutshellIntegrationTests.swift
//
// Shared integration scenarios for live Nutshell and CDK mints running
// FakeWallet backends. Exercises the cdk-swift wallet API end-to-end:
// discovery, minting, send/receive, and quote state.
//
// Requires both mints started by the scripts in CI/.

import XCTest
import Cdk

class MintIntegrationTestSuite: IntegrationTestBase {
    var mintName: String { "Cashu" }

    // MARK: - Discovery

    func runFetchMintInfo() async throws {
        let info = try await wallet.fetchMintInfo()
        XCTAssertNotNil(info, "\(mintName) mint should return mint info")
        XCTAssertFalse(info?.name?.isEmpty ?? true, "Mint name should not be empty")
    }

    func runGetMintKeysets() async throws {
        let keysets = try await wallet.keysets(policy: .refresh).filter { $0.active == true }
        XCTAssertFalse(keysets.isEmpty, "\(mintName) mint should have at least one active keyset")
        for keyset in keysets {
            XCTAssertEqual(keyset.unit, .sat, "Keyset unit should be sat")
        }
    }

    // MARK: - Minting

    func runBalanceAfterMinting() async throws {
        let initialBalance = try await wallet.totalBalance()
        XCTAssertEqual(initialBalance.value, 0, "Initial balance should be 0")
        _ = try await mintSats(100)
        let finalBalance = try await wallet.totalBalance()
        XCTAssertEqual(finalBalance.value, 100, "Balance should be 100 after minting")
    }

    func runMultipleTokensMinting() async throws {
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

    func runPrepareAndConfirmSend() async throws {
        _ = try await mintSats(50)

        let prepared = try await wallet.prepareSend(
            amount: Amount(value: 21),
            options: SendOptions(
                memo: SendMemo(memo: "\(mintName) test send", includeMemo: true),
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

    func runCancelSendKeepsBalance() async throws {
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

    func runReceiveTokenFromAnotherWallet() async throws {
        let senderDbPath = NSTemporaryDirectory().appending("\(dbNamePrefix)_sender_\(UUID().uuidString).sqlite")
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

    func runSendMoreThanBalanceThrows() async throws {
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

    func runReceiveSameTokenTwiceFailsSecondTime() async throws {
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

    func runStaleCounterReceiveRecoversAfterRestore() async throws {
        // Reproduces the production "Blinded Message is already signed" bug and the
        // fix's core mechanism. A wallet whose NUT-13 keyset counter is behind what
        // the mint has already signed for its seed (same seed, fresh DB — e.g. a
        // reinstall, or the seed running on another wallet) derives blinded receive
        // outputs the mint has already signed, so the swap is rejected. A restore()
        // rescan fast-forwards the counter past those indices, and the retry lands
        // on unused outputs. TokenService.receiveTokens automates exactly this.
        let sharedMnemonic = try generateMnemonic()
        let mintUrl = MintUrl(url: mintUrlStr)
        let opts = ReceiveOptions(
            amountSplitTarget: .none, p2pkSigningKeys: [], preimages: [], metadata: [:]
        )

        // Wallet A — shared seed, own DB. Minting 63 (= 32+16+8+4+2+1) signs blinded
        // outputs at contiguous low counter indices for this seed; the mint
        // remembers them for its lifetime.
        let walletADbPath = NSTemporaryDirectory().appending("staleA_\(UUID().uuidString).sqlite")
        let walletARepo = try WalletRepository(mnemonic: sharedMnemonic, store: .sqlite(path: walletADbPath))
        try await walletARepo.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)
        let walletA = try await walletARepo.getWallet(mintUrl: mintUrl, unit: .sat)
        _ = try await mintSats(63, wallet: walletA)

        // Sender — a *different* seed, funds a token for the receiver to claim.
        let senderDbPath = NSTemporaryDirectory().appending("staleSender_\(UUID().uuidString).sqlite")
        let senderRepo = try WalletRepository(mnemonic: try generateMnemonic(), store: .sqlite(path: senderDbPath))
        try await senderRepo.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)
        let senderWallet = try await senderRepo.getWallet(mintUrl: mintUrl, unit: .sat)
        _ = try await mintSats(40, wallet: senderWallet)
        let prepared = try await senderWallet.prepareSend(
            amount: Amount(value: 20),
            options: SendOptions(
                memo: nil, conditions: nil, amountSplitTarget: .none,
                sendKind: .onlineExact, includeFee: false, useP2bk: false,
                maxProofs: nil, metadata: [:], p2pkSigningKeys: [],
                p2pkLockedProofSendMode: .swap
            )
        )
        let tokenString = try await prepared.confirm(memo: nil).encode()

        // Wallet B — SAME seed as A, but a fresh DB → keyset counter at 0, behind
        // the mint's memory. Its receive-swap must collide at counter 0.
        let walletBDbPath = NSTemporaryDirectory().appending("staleB_\(UUID().uuidString).sqlite")
        let walletBRepo = try WalletRepository(mnemonic: sharedMnemonic, store: .sqlite(path: walletBDbPath))
        try await walletBRepo.createWallet(mintUrl: mintUrl, unit: .sat, targetProofCount: nil)
        let walletB = try await walletBRepo.getWallet(mintUrl: mintUrl, unit: .sat)

        do {
            _ = try await walletB.receive(token: try Token.decode(encodedToken: tokenString), options: opts)
            XCTFail("Expected a stale-counter collision (Blinded Message is already signed)")
        } catch {
            let msg = String(describing: error).lowercased()
            XCTAssertTrue(
                msg.contains("already signed") || msg.contains("duplicate outputs")
                    || msg.contains("outputs already signed"),
                "Expected a NUT-13 counter-desync rejection, got: \(error)"
            )
        }

        // restore() resyncs the counter past the already-signed indices…
        _ = try await walletB.restore()

        // …so the retry now lands on unused outputs and succeeds. The token's input
        // proofs were never spent by the failed swap, so it is still claimable.
        let received = try await walletB.receive(
            token: try Token.decode(encodedToken: tokenString), options: opts
        )
        XCTAssertEqual(received.value, 20, "Receive should succeed after restore resyncs the counter")

        try? FileManager.default.removeItem(atPath: walletADbPath)
        try? FileManager.default.removeItem(atPath: senderDbPath)
        try? FileManager.default.removeItem(atPath: walletBDbPath)
    }

    func runMintQuoteBalanceZeroWithoutPayment() async throws {
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

    // MARK: - BOLT12 & On-chain (CDK mint only; Nutshell's FakeWallet is bolt11-only)

    /// Polls a non-bolt11 mint quote until the FakeWallet backend registers a
    /// payment (`amount_paid` grows past `amount_issued`).
    func waitForQuotePayment(
        quoteId: String,
        method: PaymentMethod,
        wallet targetWallet: Wallet? = nil,
        timeout: TimeInterval = 15.0
    ) async throws -> MintQuote {
        let target = targetWallet ?? wallet!
        let start = Date()
        var updated = try await target.fetchMintQuote(quoteId: quoteId, paymentMethod: method)
        while updated.amountPaid.value <= updated.amountIssued.value,
              Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(nanoseconds: 200_000_000)  // 200 ms
            updated = try await target.fetchMintQuote(quoteId: quoteId, paymentMethod: method)
        }
        XCTAssertGreaterThan(
            updated.amountPaid.value, updated.amountIssued.value,
            "\(method) quote was not auto-paid by the FakeWallet within \(timeout)s"
        )
        return updated
    }

    func runBolt12SweepRecoversEveryQuoteAfterRestart() async throws {
        let dbPath = NSTemporaryDirectory()
            .appending("bolt12_recovery_\(UUID().uuidString).sqlite")
        let mnemonic = try generateMnemonic()
        let mintURL = MintUrl(url: mintUrlStr)

        let firstRepository = try WalletRepository(
            mnemonic: mnemonic,
            store: .sqlite(path: dbPath)
        )
        try await firstRepository.createWallet(
            mintUrl: mintURL,
            unit: .sat,
            targetProofCount: nil
        )
        let firstWallet = try await firstRepository.getWallet(
            mintUrl: mintURL,
            unit: .sat
        )

        let firstQuote = try await firstWallet.mintQuote(
            paymentMethod: .bolt12,
            amount: nil,
            description: nil,
            extra: nil
        )
        let secondQuote = try await firstWallet.mintQuote(
            paymentMethod: .bolt12,
            amount: nil,
            description: nil,
            extra: nil
        )
        let quotes = [firstQuote, secondQuote]
        var expectedOutstanding: UInt64 = 0
        for quote in quotes {
            let paid = try await waitForQuotePayment(
                quoteId: quote.id,
                method: .bolt12,
                wallet: firstWallet
            )
            expectedOutstanding += paid.amountPaid.value - paid.amountIssued.value
        }
        XCTAssertGreaterThan(expectedOutstanding, 0)
        let balanceBeforeRestart = try await firstWallet.totalBalance()
        XCTAssertEqual(balanceBeforeRestart.value, 0)

        // Open a fresh repository over the same durable store at the exact
        // failure boundary: payment is recorded, but no ecash was issued.
        // This deliberately proves process/database-handle recovery, not a
        // seed-only restore into an empty database. NUT-09 cannot discover a
        // mint-generated quote id, and a BOLT12 quote additionally needs its
        // stored NUT-20 signing key association. A true database-loss test
        // requires an upstream/exported quote-backup format first.
        // Keep the first FFI handle alive because explicitly destroying a CDK
        // Tokio runtime inside an async XCTest context can itself panic.
        let reopenedRepository = try WalletRepository(
            mnemonic: mnemonic,
            store: .sqlite(path: dbPath)
        )
        try await reopenedRepository.createWallet(
            mintUrl: mintURL,
            unit: .sat,
            targetProofCount: nil
        )
        let reopenedWallet = try await reopenedRepository.getWallet(
            mintUrl: mintURL,
            unit: .sat
        )

        let recovered = try await reopenedWallet.mintUnissuedQuotes()
        XCTAssertEqual(recovered.value, expectedOutstanding)
        let balanceAfterRecovery = try await reopenedWallet.totalBalance()
        XCTAssertEqual(balanceAfterRecovery.value, expectedOutstanding)

        for quote in quotes {
            let verified = try await reopenedWallet.checkMintQuote(quoteId: quote.id)
            XCTAssertEqual(verified.amountIssued.value, verified.amountPaid.value)
        }
        let secondSweep = try await reopenedWallet.mintUnissuedQuotes()
        XCTAssertEqual(secondSweep.value, 0)

        withExtendedLifetime((firstRepository, firstWallet)) {}

        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: dbPath + suffix)
        }
    }

    func runBolt12MintFlow() async throws {
        // The CDK fake backend does not advertise NUT-04 description support
        // for bolt12, so the description must stay nil.
        let quote = try await wallet.mintQuote(
            paymentMethod: .bolt12,
            amount: nil,
            description: nil,
            extra: nil
        )
        XCTAssertEqual(quote.paymentMethod, .bolt12)
        XCTAssertTrue(
            quote.request.lowercased().hasPrefix("lno1"),
            "BOLT12 mint quote should return an offer, got: \(quote.request)"
        )

        let paid = try await waitForQuotePayment(quoteId: quote.id, method: .bolt12)

        let proofs = try await wallet.mintUnified(
            quoteId: quote.id,
            amountSplitTarget: .none,
            spendingConditions: nil
        )
        let minted = proofs.reduce(UInt64(0)) { $0 + $1.amount.value }
        XCTAssertEqual(minted, paid.amountPaid.value, "Minted proofs should equal the paid amount")

        let balance = try await wallet.totalBalance()
        XCTAssertEqual(balance.value, paid.amountPaid.value, "Balance should equal the BOLT12 paid amount")
    }

    func runBolt12MeltFlow() async throws {
        // Keep payer and receiver state separate: the receiver publishes one
        // reusable offer while the payer requests a fresh invoice for each
        // entered amount.
        let offerQuote = try await wallet.mintQuote(
            paymentMethod: .bolt12,
            amount: nil,
            description: nil,
            extra: nil
        )
        let offer = offerQuote.request

        // FakeWallet seeds a newly checked amountless offer with one synthetic
        // payment. Settle that fixture credit first so the assertions below
        // measure only the two payer-generated invoice flows.
        let fixturePaid = try await waitForQuotePayment(
            quoteId: offerQuote.id,
            method: .bolt12
        )
        let fixtureOutstanding = fixturePaid.amountPaid.value - fixturePaid.amountIssued.value
        XCTAssertGreaterThan(fixtureOutstanding, 0)
        let fixtureProofs = try await wallet.mintUnified(
            quoteId: offerQuote.id,
            amountSplitTarget: .none,
            spendingConditions: nil
        )
        XCTAssertEqual(
            fixtureProofs.reduce(0) { $0 + $1.amount.value },
            fixtureOutstanding
        )
        let receiverBalanceBeforePayments = try await wallet.totalBalance()

        let payerDbPath = NSTemporaryDirectory()
            .appending("bolt12_payer_\(UUID().uuidString).sqlite")
        let payerRepository = try WalletRepository(
            mnemonic: try generateMnemonic(),
            store: .sqlite(path: payerDbPath)
        )
        let mintURL = MintUrl(url: mintUrlStr)
        try await payerRepository.createWallet(
            mintUrl: mintURL,
            unit: .sat,
            targetProofCount: nil
        )
        let payerWallet = try await payerRepository.getWallet(
            mintUrl: mintURL,
            unit: .sat
        )
        _ = try await mintSats(100, wallet: payerWallet)

        // First amount: CDK sends an invoice_request carrying 21, receives a
        // unique BOLT12 invoice, and pays it.
        let firstMeltQuote = try await payerWallet.meltQuote(
            method: .bolt12,
            request: offer,
            options: .amountless(amountMsat: Amount(value: 21_000)),
            extra: nil
        )
        XCTAssertEqual(firstMeltQuote.amount.value, 21, "First melt quote should be for 21 sats")
        let firstPrepared = try await payerWallet.prepareMelt(quoteId: firstMeltQuote.id)
        let firstFinalized = try await firstPrepared.confirm()
        XCTAssertEqual(firstFinalized.state, .paid, "First BOLT12 payment should settle")

        let firstPaid = try await waitForQuotePayment(
            quoteId: offerQuote.id,
            method: .bolt12
        )
        let firstOutstanding = firstPaid.amountPaid.value - firstPaid.amountIssued.value
        XCTAssertEqual(firstOutstanding, 21)
        let firstProofs = try await wallet.mintUnified(
            quoteId: offerQuote.id,
            amountSplitTarget: .none,
            spendingConditions: nil
        )
        XCTAssertEqual(firstProofs.reduce(0) { $0 + $1.amount.value }, 21)

        // Second amount against the same parent offer must create another
        // payment quote/invoice and expose only the new 13-sat issuance delta.
        let secondMeltQuote = try await payerWallet.meltQuote(
            method: .bolt12,
            request: offer,
            options: .amountless(amountMsat: Amount(value: 13_000)),
            extra: nil
        )
        XCTAssertEqual(secondMeltQuote.amount.value, 13, "Second melt quote should be for 13 sats")
        XCTAssertNotEqual(firstMeltQuote.id, secondMeltQuote.id)
        let secondPrepared = try await payerWallet.prepareMelt(quoteId: secondMeltQuote.id)
        let secondFinalized = try await secondPrepared.confirm()
        XCTAssertEqual(secondFinalized.state, .paid, "Second BOLT12 payment should settle")

        let secondPaid = try await waitForQuotePayment(
            quoteId: offerQuote.id,
            method: .bolt12
        )
        let secondOutstanding = secondPaid.amountPaid.value - secondPaid.amountIssued.value
        XCTAssertEqual(secondOutstanding, 13)
        let secondProofs = try await wallet.mintUnified(
            quoteId: offerQuote.id,
            amountSplitTarget: .none,
            spendingConditions: nil
        )
        XCTAssertEqual(secondProofs.reduce(0) { $0 + $1.amount.value }, 13)

        let receiverBalance = try await wallet.totalBalance()
        XCTAssertEqual(
            receiverBalance.value,
            receiverBalanceBeforePayments.value + 34,
            "Reusable offer should issue both payer-generated deltas exactly once"
        )

        let payerBalance = try await payerWallet.totalBalance()
        XCTAssertEqual(
            payerBalance.value,
            100 - 34 - firstFinalized.feePaid.value - secondFinalized.feePaid.value,
            "Payer balance should drop by both amounts plus their fees"
        )

        withExtendedLifetime((payerRepository, payerWallet)) {}
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: payerDbPath + suffix)
        }
    }

    func runOnchainMintFlow() async throws {
        let quote = try await wallet.mintQuote(
            paymentMethod: .onchain,
            amount: Amount(value: 150),
            description: nil,
            extra: nil
        )
        XCTAssertEqual(quote.paymentMethod, .onchain)
        XCTAssertTrue(
            quote.request.lowercased().hasPrefix("bcrt1"),
            "FakeWallet should hand out a regtest address, got: \(quote.request)"
        )

        // The fake backend credits its own deposit amount, so assert against
        // amount_paid rather than the requested 150.
        let paid = try await waitForQuotePayment(quoteId: quote.id, method: .onchain)

        let proofs = try await wallet.mintUnified(
            quoteId: quote.id,
            amountSplitTarget: .none,
            spendingConditions: nil
        )
        let minted = proofs.reduce(UInt64(0)) { $0 + $1.amount.value }
        XCTAssertEqual(minted, paid.amountPaid.value, "Minted proofs should equal the on-chain deposit")

        let balance = try await wallet.totalBalance()
        XCTAssertEqual(balance.value, paid.amountPaid.value, "Balance should equal the on-chain deposit")
    }

    func runOnchainMeltFlow() async throws {
        _ = try await mintSats(1000)

        // Get a regtest address to withdraw to from the fake backend itself.
        let addressQuote = try await wallet.mintQuote(
            paymentMethod: .onchain,
            amount: Amount(value: 100),
            description: nil,
            extra: nil
        )
        let address = addressQuote.request

        let feeOptions = try await wallet.quoteOnchainMeltOptions(
            address: address,
            amount: Amount(value: 300),
            maxFeeAmount: nil
        )
        XCTAssertFalse(feeOptions.isEmpty, "Mint should return at least one on-chain fee option")

        let selected = try await wallet.selectOnchainMeltQuote(quote: feeOptions[0])
        XCTAssertEqual(selected.amount.value, 300, "Selected quote should be for 300 sats")

        let prepared = try await wallet.prepareMelt(quoteId: selected.id)
        let finalized = try await prepared.confirm()
        XCTAssertEqual(finalized.state, .paid, "On-chain melt should settle against the FakeWallet")

        let balance = try await wallet.totalBalance()
        XCTAssertEqual(
            balance.value, 1000 - 300 - finalized.feePaid.value,
            "Balance should drop by withdrawal amount plus fee"
        )
    }

    // MARK: - Quote State

    func runMintQuoteStateTransitions() async throws {
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

final class NutshellIntegrationTests: MintIntegrationTestSuite {
    override var mintUrlStr: String {
        ProcessInfo.processInfo.environment["NUTSHELL_MINT_URL"] ?? "http://localhost:3338"
    }

    override var dbNamePrefix: String { "nutshell_test" }
    override var mintName: String { "Nutshell" }

    func testFetchMintInfo() async throws { try await runFetchMintInfo() }
    func testGetMintKeysets() async throws { try await runGetMintKeysets() }
    func testBalanceAfterMinting() async throws { try await runBalanceAfterMinting() }
    func testMultipleTokensMinting() async throws { try await runMultipleTokensMinting() }
    func testPrepareAndConfirmSend() async throws { try await runPrepareAndConfirmSend() }
    func testCancelSendKeepsBalance() async throws { try await runCancelSendKeepsBalance() }
    func testReceiveTokenFromAnotherWallet() async throws { try await runReceiveTokenFromAnotherWallet() }
    func testSendMoreThanBalanceThrows() async throws { try await runSendMoreThanBalanceThrows() }
    func testReceiveSameTokenTwiceFailsSecondTime() async throws { try await runReceiveSameTokenTwiceFailsSecondTime() }
    func testStaleCounterReceiveRecoversAfterRestore() async throws {
        try await runStaleCounterReceiveRecoversAfterRestore()
    }
    func testMintQuoteBalanceZeroWithoutPayment() async throws {
        try await runMintQuoteBalanceZeroWithoutPayment()
    }
    func testMintQuoteStateTransitions() async throws { try await runMintQuoteStateTransitions() }
}

final class CDKIntegrationTests: MintIntegrationTestSuite {
    override var mintUrlStr: String {
        ProcessInfo.processInfo.environment["CDK_MINT_URL"] ?? "http://localhost:3339"
    }

    override var dbNamePrefix: String { "cdk_test" }
    override var mintName: String { "CDK" }

    // BOLT12 & on-chain run only against CDK — Nutshell's FakeWallet is bolt11-only.
    func testBolt12MintFlow() async throws { try await runBolt12MintFlow() }
    func testBolt12SweepRecoversEveryQuoteAfterRestart() async throws {
        try await runBolt12SweepRecoversEveryQuoteAfterRestart()
    }
    func testBolt12MeltFlow() async throws { try await runBolt12MeltFlow() }
    func testOnchainMintFlow() async throws { try await runOnchainMintFlow() }
    func testOnchainMeltFlow() async throws { try await runOnchainMeltFlow() }

    func testFetchMintInfo() async throws { try await runFetchMintInfo() }
    func testGetMintKeysets() async throws { try await runGetMintKeysets() }
    func testBalanceAfterMinting() async throws { try await runBalanceAfterMinting() }
    func testMultipleTokensMinting() async throws { try await runMultipleTokensMinting() }
    func testPrepareAndConfirmSend() async throws { try await runPrepareAndConfirmSend() }
    func testCancelSendKeepsBalance() async throws { try await runCancelSendKeepsBalance() }
    func testReceiveTokenFromAnotherWallet() async throws { try await runReceiveTokenFromAnotherWallet() }
    func testSendMoreThanBalanceThrows() async throws { try await runSendMoreThanBalanceThrows() }
    func testReceiveSameTokenTwiceFailsSecondTime() async throws { try await runReceiveSameTokenTwiceFailsSecondTime() }
    func testStaleCounterReceiveRecoversAfterRestore() async throws {
        try await runStaleCounterReceiveRecoversAfterRestore()
    }
    func testMintQuoteBalanceZeroWithoutPayment() async throws {
        try await runMintQuoteBalanceZeroWithoutPayment()
    }
    func testMintQuoteStateTransitions() async throws { try await runMintQuoteStateTransitions() }
}
