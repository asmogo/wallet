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
}
