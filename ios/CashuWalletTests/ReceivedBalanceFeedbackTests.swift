import XCTest
@testable import CashuWallet

@MainActor
final class ReceivedBalanceFeedbackTests: XCTestCase {
    private var pendingSleeps: [CheckedContinuation<Void, Never>] = []
    private var durations: [Duration] = []

    func testReceiptDismissesAfterTwoAndAHalfSeconds() async {
        let started = expectation(description: "Dismiss timer started")
        let finished = expectation(description: "Dismiss timer finished")
        let feedback = makeFeedback(started: [started], finished: [finished])
        feedback.show(amount: 1, animation: nil)
        XCTAssertEqual(feedback.amount, 1)
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(durations, [.seconds(2.5)])

        pendingSleeps.removeFirst().resume()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertNil(feedback.amount)
    }

    func testLeavingScreenClearsReceiptBeforeTimerFinishes() async {
        let started = expectation(description: "Dismiss timer started")
        let finished = expectation(description: "Dismiss timer finished")
        let feedback = makeFeedback(started: [started], finished: [finished])
        feedback.show(amount: 1, animation: nil)
        await fulfillment(of: [started], timeout: 1)

        // The view invokes this on disappearance/backgrounding. Returning to
        // the retained view must not bring back the old amount.
        feedback.clear()
        XCTAssertNil(feedback.amount)

        pendingSleeps.removeFirst().resume()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertNil(feedback.amount)
    }

    func testRapidReceiptsGiveLatestAmountAFullDismissalTimer() async {
        await assertReplacementSurvivesCancelledTimer(nextAmount: 21, clearFirst: false)
    }

    func testRepeatedEqualReceiptsRestartDismissalTimer() async {
        await assertReplacementSurvivesCancelledTimer(nextAmount: 1, clearFirst: false)
    }

    func testNewReceiptAfterReturningSurvivesOldCancelledTimer() async {
        await assertReplacementSurvivesCancelledTimer(nextAmount: 1, clearFirst: true)
    }

    private func assertReplacementSurvivesCancelledTimer(nextAmount: UInt64, clearFirst: Bool) async {
        let firstStarted = expectation(description: "First dismiss timer started")
        let nextStarted = expectation(description: "Next dismiss timer started")
        let firstFinished = expectation(description: "First dismiss timer finished")
        let nextFinished = expectation(description: "Next dismiss timer finished")
        let feedback = makeFeedback(
            started: [firstStarted, nextStarted],
            finished: [firstFinished, nextFinished]
        )
        feedback.show(amount: 1, animation: nil)
        await fulfillment(of: [firstStarted], timeout: 1)
        if clearFirst { feedback.clear() }

        feedback.show(amount: nextAmount, animation: nil)
        await fulfillment(of: [nextStarted], timeout: 1)
        pendingSleeps.removeFirst().resume()
        await fulfillment(of: [firstFinished], timeout: 1)
        XCTAssertEqual(feedback.amount, nextAmount)
        XCTAssertEqual(durations, [.seconds(2.5), .seconds(2.5)])

        pendingSleeps.removeFirst().resume()
        await fulfillment(of: [nextFinished], timeout: 1)
        XCTAssertNil(feedback.amount)
    }

    private func makeFeedback(
        started: [XCTestExpectation],
        finished: [XCTestExpectation]
    ) -> ReceivedBalanceFeedback {
        ReceivedBalanceFeedback { duration in
            let index = self.durations.count
            self.durations.append(duration)
            // Intentionally ignore cancellation until explicitly resumed to
            // exercise the stale-timer race without waiting real seconds.
            await withCheckedContinuation { continuation in
                self.pendingSleeps.append(continuation)
                started[index].fulfill()
            }
            // The sleep and the feedback update both run on MainActor, so
            // the update completes before the waiting test resumes there.
            finished[index].fulfill()
        }
    }
}
