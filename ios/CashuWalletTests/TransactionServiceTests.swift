import XCTest
import Cdk
@testable import CashuWallet

@MainActor
final class TransactionServiceTests: XCTestCase {
    private var service: TransactionService!

    override func setUp() {
        super.setUp()
        service = TransactionService(
            walletRepository: { nil },
            walletDatabase: { nil },
            getTrackedMintUrls: { [] },
            walletStore: WalletStore(storage: InMemoryStorage())
        )
    }

    func testHomeActivityShowsOnlyLatestCompletedTransactions() {
        let now = Date()
        var completedIncoming = transaction(
            id: "received-via-request",
            status: .completed,
            date: now.addingTimeInterval(-10),
            type: .incoming
        )
        completedIncoming.cashuRequestId = "request"
        let completedOutgoing = transaction(
            id: "sent",
            status: .completed,
            date: now
        )
        let pending = transaction(
            id: "pending-request",
            status: .pending,
            date: now.addingTimeInterval(10)
        )
        let failed = transaction(
            id: "failed",
            status: .failed,
            date: now.addingTimeInterval(20)
        )
        let expired = transaction(
            id: "expired",
            status: .expired,
            date: now.addingTimeInterval(30)
        )

        let recent = HomeActivity.recentTransactions(
            from: [completedIncoming, pending, failed, completedOutgoing, expired],
            limit: 5
        )

        XCTAssertEqual(recent.map(\.id), ["sent", "received-via-request"])
        XCTAssertEqual(
            HomeActivity.recentTransactions(
                from: [completedIncoming, completedOutgoing],
                limit: 1
            ).map(\.id),
            ["sent"]
        )
    }

    // MARK: - Saved token (txId ↔ encoded token)

    func testGetTokenNilByDefault() {
        XCTAssertNil(service.getToken(txId: "nonexistent"))
    }

    func testSaveAndGetToken() {
        service.saveToken(txId: "tx1", token: "cashuAtoken123")
        XCTAssertEqual(service.getToken(txId: "tx1"), "cashuAtoken123")
    }

    func testSaveTokenOverwritesPrevious() {
        service.saveToken(txId: "tx1", token: "cashuAold")
        service.saveToken(txId: "tx1", token: "cashuAnew")
        XCTAssertEqual(service.getToken(txId: "tx1"), "cashuAnew")
    }

    func testSaveMultipleTokensIndependently() {
        service.saveToken(txId: "a", token: "cashuAaaa")
        service.saveToken(txId: "b", token: "cashuAbbb")
        XCTAssertEqual(service.getToken(txId: "a"), "cashuAaaa")
        XCTAssertEqual(service.getToken(txId: "b"), "cashuAbbb")
    }

    func testTransactionIdLookupByTokenString() {
        XCTAssertNil(service.transactionId(forToken: "cashuAmissing"))
        service.saveToken(txId: "tx1", token: "cashuAtoken123")
        XCTAssertEqual(service.transactionId(forToken: "cashuAtoken123"), "tx1")
    }

    // MARK: - Preimage (quoteId ↔ preimage)

    func testGetPreimageNilByDefault() {
        XCTAssertNil(service.getPreimage(quoteId: "nonexistent"))
    }

    func testSaveAndGetPreimage() {
        service.savePreimage(quoteId: "quote1", preimage: "deadbeef")
        XCTAssertEqual(service.getPreimage(quoteId: "quote1"), "deadbeef")
    }

    func testSaveMultiplePreimagesIndependently() {
        service.savePreimage(quoteId: "q1", preimage: "pre1")
        service.savePreimage(quoteId: "q2", preimage: "pre2")
        XCTAssertEqual(service.getPreimage(quoteId: "q1"), "pre1")
        XCTAssertEqual(service.getPreimage(quoteId: "q2"), "pre2")
    }

    // MARK: - Manual pending-send claim checks

    func testManualClaimCheckIsOnlyOfferedWhenAutomaticChecksAreDisabled() {
        var pending = transaction(id: "manual", status: .pending, date: Date())
        pending.token = "cashuAtokenmanual"
        pending.sagaId = "operation-id"

        XCTAssertTrue(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled: false,
                transaction: pending
            )
        )
        XCTAssertFalse(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled: true,
                transaction: pending
            )
        )

        let completed = transaction(id: "settled", status: .completed, date: Date())
        XCTAssertFalse(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled: false,
                transaction: completed
            )
        )
    }

    func testIsPendingSentTokenMatchesOnlyUnclaimedOutgoingEcash() {
        var pending = transaction(id: "p", status: .pending, date: Date())
        pending.token = "cashuAtokenp"
        XCTAssertTrue(isPendingSentToken(pending))

        // Without the token string the row is not actionable (no QR/Copy).
        var tokenless = transaction(id: "t", status: .pending, date: Date())
        tokenless.sagaId = "operation-id"
        XCTAssertFalse(isPendingSentToken(tokenless))

        var incoming = transaction(id: "i", status: .pending, date: Date(), type: .incoming)
        incoming.token = "cashuAtokeni"
        XCTAssertFalse(isPendingSentToken(incoming))

        var claimed = transaction(id: "c", status: .completed, date: Date())
        claimed.token = "cashuAtokenc"
        XCTAssertFalse(isPendingSentToken(claimed))
    }

    func testPendingTokenClaimCheckDistinguishesAllOutcomes() async throws {
        let claimed = try await runPendingTokenClaimCheck { true }
        guard case .claimed = claimed else {
            return XCTFail("Expected claimed result")
        }

        let notClaimed = try await runPendingTokenClaimCheck { false }
        guard case .notClaimed = notClaimed else {
            return XCTFail("Expected not-claimed result")
        }

        let failed = try await runPendingTokenClaimCheck {
            throw WalletError.networkError("network connection failed")
        }
        guard case .failed(let message) = failed else {
            return XCTFail("Expected failed result")
        }
        XCTAssertEqual(
            message.text,
            "Couldn't reach the mint. Check your connection and try again."
        )
        XCTAssertEqual(message.recoverability, .retryable)
    }

    func testPendingTokenClaimCheckPreservesCancellation() async {
        do {
            _ = try await runPendingTokenClaimCheck {
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: leaving the screen must cancel instead of showing an error.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - Pending Receive Tokens

    func testPendingReceiveTokensEmptyInitially() {
        XCTAssertTrue(service.pendingReceiveTokens.isEmpty)
    }

    func testSavePendingReceiveToken() {
        service.savePendingReceiveToken(receiveToken(id: "r1", amount: 50))
        XCTAssertEqual(service.pendingReceiveTokens.count, 1)
        XCTAssertEqual(service.pendingReceiveTokens[0].tokenId, "r1")
    }

    func testSavePendingReceiveTokenUpdatesExisting() {
        service.savePendingReceiveToken(receiveToken(id: "r1", amount: 10))
        service.savePendingReceiveToken(receiveToken(id: "r1", amount: 99))
        XCTAssertEqual(service.pendingReceiveTokens.count, 1)
        XCTAssertEqual(service.pendingReceiveTokens[0].amount, 99)
    }

    func testSavePendingReceiveTokenDeduplicatesSameEcash() {
        service.savePendingReceiveToken(receiveToken(id: "r1", token: "cashuAsame", amount: 10))
        service.savePendingReceiveToken(receiveToken(id: "r2", token: "cashuAsame", amount: 99))

        XCTAssertEqual(service.pendingReceiveTokens.count, 1)
        XCTAssertEqual(service.pendingReceiveTokens[0].tokenId, "r1")
        XCTAssertEqual(service.pendingReceiveTokens[0].amount, 99)
    }

    func testRemovePendingReceiveToken() {
        service.savePendingReceiveToken(receiveToken(id: "r1", amount: 10))
        service.savePendingReceiveToken(receiveToken(id: "r2", amount: 20))
        service.removePendingReceiveToken(tokenId: "r1")
        XCTAssertEqual(service.pendingReceiveTokens.count, 1)
        XCTAssertEqual(service.pendingReceiveTokens[0].tokenId, "r2")
    }

    // MARK: - clearState

    func testClearStateEmptiesAllCollections() {
        service.savePendingReceiveToken(receiveToken(id: "r", amount: 2))
        service.clearState()
        XCTAssertTrue(service.pendingReceiveTokens.isEmpty)
        XCTAssertTrue(service.transactions.isEmpty)
    }



    // MARK: - Detail lookup (quote-row → transaction-row follow)

    func testLiveDetailPrefersExactIdMatch() {
        let open = transaction(id: "quote-1", status: .pending, date: Date())
        let other = WalletTransaction(
            id: "cdk-9", amount: 1, type: .incoming, kind: .lightning,
            date: Date(), memo: nil, status: .completed
        )

        XCTAssertEqual([other, open].liveDetail(openId: "quote-1")?.id, "quote-1")
    }

    func testLiveDetailFallsBackToQuoteIdAfterMintSwap() {
        // The pending row's id was the quote id; after minting, only the CDK
        // transaction (saga-derived id, same quoteId) remains.
        var completed = transaction(id: "cdk-9", status: .completed, date: Date())
        completed.quoteId = "quote-1"
        let unrelated = transaction(id: "other", status: .completed, date: Date())

        let resolved = [unrelated, completed].liveDetail(openId: "quote-1", openQuoteId: "quote-1")

        XCTAssertEqual(resolved?.id, "cdk-9")
    }

    func testLiveDetailResolvesReusableOfferToNewestPayment() {
        // Rows are stored newest-first; several payments share one offer's
        // quoteId, so the fallback yields the latest one.
        var newer = transaction(id: "cdk-2", status: .completed, date: Date())
        newer.quoteId = "offer"
        var older = transaction(id: "cdk-1", status: .completed, date: Date(timeIntervalSince1970: 100))
        older.quoteId = "offer"

        XCTAssertEqual(
            [newer, older].liveDetail(openId: "offer", openQuoteId: "offer")?.id,
            "cdk-2"
        )
    }

    func testLiveDetailReturnsNilWhenNothingMatches() {
        XCTAssertNil(
            [transaction(id: "a", status: .completed, date: Date())]
                .liveDetail(openId: "missing", openQuoteId: "also-missing")
        )
    }

    // MARK: - Unpaid / expired invoice display

    func testUnpaidInvoiceTitlesAsInvoiceUntilPaid() {
        var transaction = WalletTransaction(
            id: "quote",
            amount: 500,
            type: .incoming,
            kind: .lightning,
            date: Date(),
            memo: nil,
            status: .pending
        )
        transaction.isUnpaidInvoice = true

        XCTAssertEqual(transaction.displayTitle, "Lightning invoice")

        transaction.isUnpaidInvoice = false
        XCTAssertEqual(transaction.displayTitle, "Lightning received")
    }

    func testExpiredStatusDisplayAndQuietPending() {
        var transaction = WalletTransaction(
            id: "quote",
            amount: 500,
            type: .incoming,
            kind: .lightning,
            date: Date(),
            memo: nil,
            status: .expired
        )
        transaction.isUnpaidInvoice = true

        XCTAssertEqual(transaction.status.displayText, "Expired")
        XCTAssertEqual(transaction.displayStatusText, "Expired")
        XCTAssertEqual(transaction.displayTitle, "Lightning invoice")
        XCTAssertTrue(transaction.isUnsettled)
        XCTAssertFalse(WalletTransaction(
            id: "settled",
            amount: 500,
            type: .incoming,
            kind: .lightning,
            date: Date(),
            memo: nil,
            status: .completed
        ).isUnsettled)
    }

    // MARK: - Helpers

    private func transaction(
        id: String,
        status: WalletTransaction.TransactionStatus,
        date: Date,
        type: WalletTransaction.TransactionType = .outgoing
    ) -> WalletTransaction {
        WalletTransaction(
            id: id,
            amount: 1,
            type: type,
            kind: .ecash,
            date: date,
            memo: nil,
            status: status
        )
    }

    private func receiveToken(id: String, token: String? = nil, amount: UInt64) -> PendingReceiveToken {
        PendingReceiveToken(
            tokenId: id,
            token: token ?? "cashuArecv\(id)",
            amount: amount,
            date: Date(),
            mintUrl: "https://mint.example.com"
        )
    }
}

@MainActor
final class MintQuoteContextPolicyTests: XCTestCase {
    private let mintA = "https://mint-a.example"
    private let mintB = "https://mint-b.example"

    func testServiceReopensOfferForRequestedMintAndUnit() async throws {
        let database = try WalletSqliteDatabase.newInMemory()
        for quote in [
            quote(id: "offer-b-usd", mintURL: mintB, unit: .usd),
            quote(id: "offer-a-sat", mintURL: mintA, unit: .sat),
            quote(id: "offer-a-usd", mintURL: mintA, unit: .usd)
        ] {
            try await database.addMintQuote(quote: quote)
        }
        let service = LightningService(
            walletRepository: { nil },
            walletDatabase: { database },
            getActiveMint: { nil }
        )

        let aUSD = try await service.existingAmountlessOffer(mintURL: mintA, unit: .usd)
        let aSAT = try await service.existingAmountlessOffer(mintURL: mintA, unit: .sat)
        let bUSD = try await service.existingAmountlessOffer(mintURL: mintB, unit: .usd)

        XCTAssertEqual(aUSD?.id, "offer-a-usd")
        XCTAssertEqual(aUSD?.unit, "usd")
        XCTAssertEqual(aUSD?.mintURL, mintA)
        XCTAssertEqual(aSAT?.id, "offer-a-sat")
        XCTAssertEqual(aSAT?.unit, "sat")
        XCTAssertEqual(aSAT?.mintURL, mintA)
        XCTAssertEqual(bUSD?.id, "offer-b-usd")
        XCTAssertEqual(bUSD?.mintURL, mintB)
    }

    func testAmountlessOfferSelectionDoesNotCrossMintOrUnit() throws {
        let quotes = [
            quote(id: "wrong-method", mintURL: mintA, unit: .usd, paymentMethod: .bolt11),
            quote(id: "fixed-a-usd", mintURL: mintA, unit: .usd, amount: 500),
            quote(id: "offer-b-usd", mintURL: mintB, unit: .usd),
            quote(id: "offer-a-sat", mintURL: mintA, unit: .sat),
            quote(id: "offer-a-usd", mintURL: mintA, unit: .usd),
            quote(id: "offer-b-sat", mintURL: mintB, unit: .sat)
        ]

        XCTAssertEqual(
            MintQuoteContextPolicy.existingAmountlessOffer(
                in: quotes,
                requestedContext: MintQuoteWalletContext(mintURL: mintA, unit: .usd)
            )?.id,
            "offer-a-usd"
        )
        XCTAssertEqual(
            MintQuoteContextPolicy.existingAmountlessOffer(
                in: quotes,
                requestedContext: MintQuoteWalletContext(mintURL: mintA, unit: .sat)
            )?.id,
            "offer-a-sat"
        )
        XCTAssertEqual(
            MintQuoteContextPolicy.existingAmountlessOffer(
                in: quotes,
                requestedContext: MintQuoteWalletContext(mintURL: mintB, unit: .usd)
            )?.id,
            "offer-b-usd"
        )
        XCTAssertNil(
            MintQuoteContextPolicy.existingAmountlessOffer(
                in: quotes,
                requestedContext: MintQuoteWalletContext(mintURL: mintB, unit: .eur)
            )
        )
    }

    func testStoredQuoteContextPreservesMintAndUnitAndMissingContextFailsClosed() {
        for unit: Cdk.CurrencyUnit in [.sat, .usd] {
            let storedQuote = quote(id: "offer", mintURL: mintA, unit: unit)
            let resolved = MintQuoteContextPolicy.walletContext(storedQuote: storedQuote)

            XCTAssertEqual(
                resolved,
                MintQuoteWalletContext(mintURL: mintA, unit: unit)
            )
        }

        XCTAssertNil(MintQuoteContextPolicy.walletContext(storedQuote: nil))
    }

    private func quote(
        id: String,
        mintURL: String,
        unit: Cdk.CurrencyUnit,
        amount: UInt64? = nil,
        paymentMethod: Cdk.PaymentMethod = .bolt12
    ) -> MintQuote {
        MintQuote(
            id: id,
            amount: amount.map { Amount(value: $0) },
            unit: unit,
            request: "request-\(id)",
            state: .unpaid,
            expiry: 0,
            mintUrl: MintUrl(url: mintURL),
            amountIssued: Amount(value: 0),
            amountPaid: Amount(value: 0),
            updatedAt: 0,
            estimatedBlocks: nil,
            paymentMethod: paymentMethod,
            secretKey: nil,
            usedByOperation: nil,
            version: 0
        )
    }
}

@MainActor
final class HistoryDescriptionTests: XCTestCase {
    private let offer = "lno1pg95xmmxvejk2g8sn7xtz93pqfumuen7l8wthtz45p3ftn58pvrs9xlumvkuu2xet8egzkcklqtes"
    private let expectedDescription = "Coffee 🌱"

    private func payment(_ id: String = "payment", type: WalletTransaction.TransactionType = .incoming) -> WalletTransaction {
        var tx = WalletTransaction(id: id, amount: 21, type: type, kind: .lightning,
            date: Date(), memo: nil, status: .completed, mintUrl: "https://mint.example/")
        tx.quoteId = "quote"
        return tx
    }

    func testPaidReusableRequestAndEveryReceiptKeepDescriptionAfterStoreReload() throws {
        let suite = "HistoryDescriptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CashuRequestStore(userDefaults: defaults)
        let request = store.upsertQuoteIntent(rail: .bolt12, quoteId: "quote", encoded: offer,
            mints: ["https://mint.example"], reusable: true)
        store.attachPayment(requestId: request.id, transactionId: "first", amount: 21)
        store.attachPayment(requestId: request.id, transactionId: "second", amount: 42)
        let reloaded = WalletStore(storage: UserDefaultsStorage(defaults: defaults)).loadCashuRequests()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.totalReceived, 63)
        XCTAssertEqual(reloaded.first?.displayDescription, expectedDescription)
        for id in ["first", "second"] {
            let receipt = payment(id).restoringDescription(from: reloaded)
            XCTAssertEqual(receipt.memo, expectedDescription)
            XCTAssertTrue(HistorySearch.matches(query: "coffee", transaction: receipt))
        }
        XCTAssertTrue(HistorySearch.matches(query: "coffee", request: try XCTUnwrap(reloaded.first), receivedTotal: 63))
    }

    func testOutgoingInvoiceRecoversDescriptionWithoutLocalRequest() {
        var tx = payment(type: .outgoing)
        tx.invoice = offer
        XCTAssertEqual(tx.restoringDescription(from: []).memo, expectedDescription)
        tx.status = .pending
        XCTAssertEqual(tx.displayDescription, expectedDescription)
    }

    func testQuoteLinkDoesNotCopyDescriptionFromAnotherMintUnitOrDirection() {
        let request = CashuRequest(encoded: offer, mints: ["https://mint.example"], rail: .bolt12, quoteId: "quote")
        var wrongMint = payment()
        wrongMint.mintUrl = "https://other.example"
        var wrongUnit = payment()
        wrongUnit.unit = "usd"
        for tx in [wrongMint, wrongUnit, payment(type: .outgoing)] {
            XCTAssertNil(tx.restoringDescription(from: [request]).memo)
        }
        XCTAssertEqual(payment().restoringDescription(from: [request]).memo, expectedDescription)
    }

    func testLocalMemoTakesPrecedenceAndEmptyDescriptionsStayHidden() {
        var tx = payment()
        tx.invoice = offer
        tx.memo = "Personal memo"
        XCTAssertEqual(tx.displayDescription, "Personal memo")
        tx.invoice = nil
        tx.memo = " \n "
        XCTAssertNil(tx.displayDescription)
        XCTAssertNil(CashuRequest(encoded: "invalid", memo: " ").displayDescription)
    }

    func testHashedDescriptionIsAReferenceWithoutChangingStoredText() {
        let hash = String(repeating: "0123456789abcdef", count: 4)
        for type: WalletTransaction.TransactionType in [.incoming, .outgoing] {
            var tx = payment(type: type)
            tx.memo = "Hash: \(hash)"
            XCTAssertEqual(tx.descriptionHash, hash)
            XCTAssertEqual(tx.displayDescription, tx.memo)
            XCTAssertEqual(PaymentRequestDecoder.middleTruncated(hash), "01234567…abcdef")
            tx.memo = " \nHash:\n\(hash.uppercased()) \n"
            XCTAssertEqual(tx.descriptionHash, hash.uppercased())
        }
    }

    func testOrdinaryDescriptionsAreNotMistakenForHashReferences() {
        let hash = String(repeating: "a", count: 64)
        var tx = payment()
        for memo in ["Hash: breakfast", "Hash: \(hash) extra", "Hash: \(hash.dropLast())",
                     "Hash: \(String(repeating: "g", count: 64))", hash, "Personal memo"] {
            tx.memo = memo
            XCTAssertNil(tx.descriptionHash)
            XCTAssertEqual(tx.displayDescription, memo)
        }
        let ecash = WalletTransaction(id: "ecash", amount: 21, type: .incoming, kind: .ecash,
            date: Date(), memo: "Hash: \(hash)", status: .completed)
        XCTAssertNil(ecash.descriptionHash)
    }

    func testCashuRequestDescriptionSurvivesClaimedReceiptWithoutInvoice() {
        let request = CashuRequest(id: "cashu", encoded: "creq", memo: expectedDescription,
            receivedPayments: [.init(transactionId: "payment", amount: 21, receivedAt: Date())])
        var tx = payment()
        tx.quoteId = nil
        XCTAssertEqual(tx.restoringDescription(from: [request]).memo, expectedDescription)
    }
}
