import XCTest
import Cdk
@testable import CashuWallet

/// The bounded settlement wait for async (NUT-05) lightning melts: CDK's
/// `PendingMelt.wait()` does the polling; the app only races it against a
/// fallback cap. These drive the race with injected closures — no CDK runtime
/// needed, since `FinalizedMelt` is a plain struct with a public initializer.
@MainActor
final class MeltSettlementWaitTests: XCTestCase {

    private func makeService() -> LightningService {
        LightningService(
            walletRepository: { nil },
            walletDatabase: { nil },
            getActiveMint: { nil }
        )
    }

    private func finalized(state: QuoteState = .paid) -> FinalizedMelt {
        FinalizedMelt(
            quoteId: "quote",
            state: state,
            preimage: "preimage",
            change: nil,
            amount: Amount(value: 10),
            feePaid: Amount(value: 2)
        )
    }

    func testFastSettlementWinsTheRace() async {
        let outcome = await makeService().awaitMeltSettlementBounded(cap: .seconds(5)) {
            self.finalized()
        }
        guard case .finalized(let value) = outcome else {
            return XCTFail("expected .finalized, got \(outcome)")
        }
        XCTAssertEqual(value.preimage, "preimage")
        XCTAssertEqual(value.feePaid.value, 2)
    }

    func testThrownWaitReportsFailure() async {
        struct WaitError: Error {}
        let outcome = await makeService().awaitMeltSettlementBounded(cap: .seconds(5)) {
            throw WaitError()
        }
        guard case .failed = outcome else {
            return XCTFail("expected .failed, got \(outcome)")
        }
    }

    func testCapExpiryHandsBackTheResidualWatcher() async throws {
        let outcome = await makeService().awaitMeltSettlementBounded(cap: .milliseconds(50)) {
            // Outlives the cap, then settles — the residual watcher must still
            // deliver the finalized melt afterwards.
            try await Task.sleep(for: .milliseconds(300))
            return self.finalized()
        }
        guard case .capExpired(let residual) = outcome else {
            return XCTFail("expected .capExpired, got \(outcome)")
        }
        let settled = try await residual.value
        XCTAssertEqual(settled.state, .paid)
    }

    /// The finish and the cap landing together must resume exactly once —
    /// whichever outcome wins is acceptable; a double resume would crash.
    func testNearSimultaneousFinishAndCapResumesOnce() async {
        let outcome = await makeService().awaitMeltSettlementBounded(cap: .milliseconds(50)) {
            try await Task.sleep(for: .milliseconds(50))
            return self.finalized()
        }
        switch outcome {
        case .finalized, .capExpired:
            break
        case .failed(let error):
            XCTFail("unexpected failure: \(error)")
        }
    }

    func testUncancellableResidualBlocksWalletBoundaryUntilNativeWaitReturns() async throws {
        let service = makeService()
        let (residual, finish) = await holdSettlement(service: service)

        XCTAssertThrowsError(try service.requireNoActiveMeltSettlement())
        service.clearState()
        residual.cancel()
        XCTAssertThrowsError(try service.requireNoActiveMeltSettlement(),
                             "Clearing UI state or cancelling Swift must not hide a live native wait")

        finish.resume(returning: finalized())
        _ = try await residual.value
        XCTAssertNoThrow(try service.requireNoActiveMeltSettlement())
    }

    func testWalletBoundaryWaitsForEveryNativeSettlement() async throws {
        struct WaitError: Error {}
        let service = makeService()
        let (residual, finish) = await holdSettlement(service: service)
        let (otherResidual, finishOther) = await holdSettlement(service: service)
        XCTAssertThrowsError(try service.requireNoActiveMeltSettlement())

        finish.resume(throwing: WaitError())
        _ = await residual.result
        XCTAssertThrowsError(try service.requireNoActiveMeltSettlement(),
                             "A failed wait must not release another live settlement")

        finishOther.resume(returning: finalized())
        _ = try await otherResidual.value
        XCTAssertNoThrow(try service.requireNoActiveMeltSettlement())
    }

    func testCreateAndDeleteRejectActiveSettlementBeforeTouchingWalletState() async throws {
        let manager = WalletManager()
        let (residual, finish) = await holdSettlement(service: manager.lightningService)

        do {
            try await manager.createNewWallet()
            XCTFail("Creation must not replace files while a native settlement is active")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("still settling"))
        }
        do {
            try await manager.deleteWallet()
            XCTFail("Deletion must not remove files while a native settlement is active")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("still settling"))
        }
        XCTAssertNil(manager.walletRepository)
        XCTAssertFalse(manager.isLoading)

        finish.resume(returning: finalized())
        _ = try await residual.value
    }

    private func holdSettlement(service: LightningService) async -> (
        Task<FinalizedMelt, any Error>, CheckedContinuation<FinalizedMelt, any Error>
    ) {
        let started = expectation(description: "Native settlement started")
        var finish: CheckedContinuation<FinalizedMelt, any Error>?
        let race = Task {
            await service.awaitMeltSettlementBounded(cap: .zero) {
                try await withCheckedThrowingContinuation { continuation in
                    finish = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        guard case .capExpired(let residual) = await race.value, let finish else {
            preconditionFailure("Held settlement must outlive the cap")
        }
        return (residual, finish)
    }
}
