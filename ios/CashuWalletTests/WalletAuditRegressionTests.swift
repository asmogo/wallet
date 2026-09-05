import Cdk
import XCTest
@testable import CashuWallet

@MainActor
final class WalletAuditRegressionTests: XCTestCase {
    private enum Failure: Error { case offline }

    func testMeltAmountRejectsOverflowingFee() throws {
        XCTAssertEqual(try LightningService.requiredMeltAmount(amount: 10, feeReserve: 2), 12)
        XCTAssertThrowsError(try LightningService.requiredMeltAmount(amount: .max, feeReserve: 1))
        let quote = MeltQuoteInfo(id: "quote", mintUrl: "https://mint.example", amount: .max, feeReserve: 1, paymentMethod: .bolt11, state: .pending, expiry: nil)
        XCTAssertEqual(quote.totalAmount, .max)
    }

    func testLightningServiceMintsIntoTheQuotesWalletAfterActiveMintChanges() async throws {
        let mintURL = ProcessInfo.processInfo.environment["NUTSHELL_MINT_URL"] ?? "http://localhost:3338"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        weak var releasedDatabase: LifecycleSafeWalletDatabase?
        do {
            let database = try LifecycleSafeWalletDatabase(filePath: directory.appendingPathComponent("wallet.sqlite").path)
            releasedDatabase = database
            let repository = try WalletRepository(mnemonic: generateMnemonic(), store: customWalletStore(db: database))
            try await repository.createWallet(mintUrl: MintUrl(url: mintURL), unit: .sat, targetProofCount: nil)
            var active = MintInfo(url: mintURL, name: "Test mint", isActive: true, balance: 0)
            let service = LightningService(walletRepository: { repository }, walletDatabase: { database }, getActiveMint: { active })
            var quote = try await service.createMintQuote(amount: 16)
            active = MintInfo(url: "https://other.example", name: "Other mint", isActive: true, balance: 0)
            for _ in 0..<50 where quote.state == .pending {
                try await Task.sleep(for: .milliseconds(100))
                quote = try await service.checkMintQuote(quoteId: quote.id)
            }
            XCTAssertEqual(quote.state, .paid)
            let received = try await service.mintTokens(quoteId: quote.id)
            XCTAssertEqual(received, 16)
            let wallet = try await repository.getWallet(mintUrl: MintUrl(url: mintURL), unit: .sat)
            let balance = try await wallet.totalBalance().value
            XCTAssertEqual(balance, 16)
        }
        // The native writer may be the last owner. Give teardown time to run
        // inside this test so a regression is attributed to the wallet lifecycle.
        let deadline = Date().addingTimeInterval(3)
        while releasedDatabase != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(releasedDatabase)
    }

    func testPaymentSurfacesDistinguishPayloadsWithIdenticalPrefixes() {
        let prefix = String(repeating: "a", count: 80)
        XCTAssertNotEqual(FlowCover.receiveToken(prefix + "1").id, FlowCover.receiveToken(prefix + "2").id)
        XCTAssertNotEqual(WalletSheet.meltInvoice(prefix + "1").id, WalletSheet.meltInvoice(prefix + "2").id)
    }

    func testMintIdentitiesPreserveSchemePathAndHostBoundaries() {
        XCTAssertNotEqual(MintURLIdentity.normalized("https://mint.example/a"), MintURLIdentity.normalized("https://mint.examplea"))
        XCTAssertNotEqual(MintURLIdentity.normalized("https://mint.example/A"), MintURLIdentity.normalized("https://mint.example/a"))
        XCTAssertNotEqual(MintURLIdentity.normalized("http://mint.example"), MintURLIdentity.normalized("https://mint.example"))
        XCTAssertEqual(MintURLIdentity.normalized(" HTTPS://MINT.EXAMPLE:443/a/ "), "https://mint.example/a")
    }

    func testReceiveFeeRoundsOnceAcrossKeysetsAndCachesLookups() async throws {
        var lookedUp: [String] = []
        let fee = try await TokenService.receiveFee(keysetIDs: ["a", "b", "a"]) { key in
            lookedUp.append(key)
            return key == "a" ? 100 : 800
        }
        XCTAssertEqual(fee, 1)
        XCTAssertEqual(lookedUp, ["a", "b"])
        let rounded = try await TokenService.receiveFee(keysetIDs: ["a"]) { _ in 1001 }
        XCTAssertEqual(rounded, 2)
    }

    func testUnknownReceiveFeePropagatesFailureInsteadOfReportingZero() async {
        do {
            _ = try await TokenService.receiveFee(keysetIDs: ["missing"]) { _ in throw Failure.offline }
            XCTFail("Unknown fees must not be presented as free")
        } catch { XCTAssertTrue(error is Failure) }
    }

    func testExcessiveReceiveFeeCannotOverflow() async throws {
        let single = try await TokenService.receiveFee(keysetIDs: ["a"]) { _ in UInt64.max }
        XCTAssertEqual(single, UInt64.max / 1000 + 1)
        do {
            _ = try await TokenService.receiveFee(keysetIDs: ["a", "a"]) { _ in UInt64.max }
            XCTFail("An invalid fee must fail without trapping")
        } catch { }
    }

    func testUnresolvedMintRecoveryBlocksAnotherMintAttempt() async {
        let original = quote(reservation: "operation")
        var didRecover = false
        do {
            _ = try await MintQuoteRecovery.reconcile(
                quote: original,
                recover: { didRecover = true },
                reload: { original }
            )
            XCTFail("A reserved quote must remain blocked")
        } catch { }
        XCTAssertTrue(didRecover)
    }

    func testRecoveredMintReturnsOnlyNewlyIssuedAmount() async throws {
        let recovered = try await MintQuoteRecovery.reconcile(
            quote: quote(reservation: "operation", issued: 5),
            recover: {},
            reload: { self.quote(reservation: nil, issued: 12) }
        )
        XCTAssertEqual(recovered, 7)
    }

    func testRecoveryReadFailureDoesNotPermitRetry() async {
        do {
            _ = try await MintQuoteRecovery.reconcile(
                quote: quote(reservation: "operation"), recover: {},
                reload: { throw Failure.offline }
            )
            XCTFail("Failure to inspect the reservation must fail closed")
        } catch { XCTAssertTrue(error is Failure) }
    }

    func testStaleQuoteUpdatePreservesStoredReservation() async throws {
        let database = try WalletSqliteDatabase.newInMemory()
        let original = quote(reservation: nil)
        try await database.addMintQuote(quote: original)
        let operationID = UUID().uuidString
        try await database.reserveMintQuote(quoteId: original.id, operationId: operationID)
        let service = LightningService(walletRepository: { nil }, walletDatabase: { database }, getActiveMint: { nil })
        // The stale version must never be installed by deleting the newer row.
        do { try await service.replaceStoredMintQuote(original, in: database) } catch { }
        let stored = try await database.getMintQuote(quoteId: original.id)
        XCTAssertEqual(stored?.usedByOperation, operationID.lowercased())
        XCTAssertEqual(stored?.request, original.request)
    }

    func testNWCRejectsLimitThatWouldOverflowMillisatoshis() throws {
        XCTAssertNil(try NWCManager.paymentLimitMsat(nil))
        XCTAssertEqual(try NWCManager.paymentLimitMsat(100), 100_000)
        XCTAssertThrowsError(try NWCManager.paymentLimitMsat(UInt64.max))
    }

    func testDisablingNWCDuringStartupDiscardsLateFailure() async {
        let settings = SettingsStore(storage: InMemoryStorage())
        settings.nwcEnabled = true
        settings.nwcSelectedMint = "https://mint.example"
        let manager = NWCManager(settingsStore: settings)
        let started = expectation(description: "Wallet lookup started")
        var continuation: CheckedContinuation<Wallet, Error>?
        manager.configure(walletProvider: { _ in
            try await withCheckedThrowingContinuation {
                continuation = $0
                started.fulfill()
            }
        }, seedProvider: { Data(repeating: 1, count: 64) })
        let startup = Task { await manager.start() }
        await fulfillment(of: [started], timeout: 3)
        manager.isEnabled = false
        continuation?.resume(throwing: Failure.offline)
        await startup.value
        await manager.stop()
        XCTAssertFalse(manager.isRunning)
        XCTAssertFalse(manager.isBusy)
        XCTAssertNil(manager.connectionUri)
        XCTAssertNil(manager.errorMessage)
    }

    func testWalletBoundaryCancelsQueuedOldRepositoryWork() async throws {
        let coordinator = WalletOperationCoordinator(watchdogThreshold: 0)
        let entered = expectation(description: "Boundary holds the lane")
        var release: CheckedContinuation<Void, Never>?
        let boundary = Task {
            try await coordinator.perform(kind: .recovery) {
                await withCheckedContinuation {
                    release = $0
                    entered.fulfill()
                }
                await coordinator.cancelPendingOperations()
            }
        }
        await fulfillment(of: [entered], timeout: 3)
        let pending = Task {
            try await coordinator.perform(kind: .send) { XCTFail("Old repository work ran after replacement") }
        }
        let deadline = Date().addingTimeInterval(3)
        while await coordinator.snapshot().waitingCount == 0, Date() < deadline { await Task.yield() }
        let queued = await coordinator.snapshot().waitingCount
        XCTAssertEqual(queued, 1)
        release?.resume()
        try await boundary.value
        do {
            try await pending.value
            XCTFail("Expected cancellation at the wallet boundary")
        } catch { XCTAssertTrue(error is CancellationError) }
        try await coordinator.perform(kind: .balance) {}
    }

    private func quote(reservation: String?, issued: UInt64 = 0) -> MintQuote {
        MintQuote(
            id: "quote", amount: nil, unit: .sat, request: "receive-request", state: .paid,
            expiry: 0, mintUrl: MintUrl(url: "https://mint.example"),
            amountIssued: Amount(value: issued), amountPaid: Amount(value: 12), updatedAt: 0,
            estimatedBlocks: nil, paymentMethod: .bolt12, secretKey: nil,
            usedByOperation: reservation, version: 0
        )
    }
}
