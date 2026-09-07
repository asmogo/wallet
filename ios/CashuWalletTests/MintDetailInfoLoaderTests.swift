import XCTest
@testable import CashuWallet

@MainActor
final class MintDetailInfoLoaderTests: XCTestCase {
    func testCancellationErrorsDoNotShowFailureOrLeaveLoading() async {
        for error in [CancellationError(), URLError(.cancelled)] as [Error] {
            let loader = MintDetailInfoLoader<String>()
            await loader.load { throw error }

            XCTAssertNil(loader.errorMessage)
            XCTAssertNil(loader.info)
            XCTAssertFalse(loader.isLoading)
            XCTAssertEqual(loader.connection, .notChecked)
        }
    }

    func testCancelledNativeRequestCannotPublishSuccessOrFailure() async {
        for result in [Result<String?, Error>.success("late"), .failure(URLError(.timedOut))] {
            let loader = MintDetailInfoLoader<String>()
            let fetch = SuspendedFetch()
            let task = Task { await loader.load { try await fetch.value() } }
            await fulfillment(of: [fetch.started], timeout: 2)
            task.cancel()
            fetch.finish(with: result)
            await task.value

            XCTAssertNil(loader.info)
            XCTAssertNil(loader.errorMessage)
            XCTAssertFalse(loader.isLoading)
            XCTAssertEqual(loader.connection, .notChecked)
        }
    }

    func testCancelledRefreshPreservesLoadedInformation() async {
        let loader = MintDetailInfoLoader<String>()
        await loader.load { "saved" }
        await loader.load { throw CancellationError() }

        XCTAssertEqual(loader.info, "saved")
        XCTAssertNil(loader.errorMessage)
        XCTAssertEqual(loader.connection, .notChecked)
    }

    func testFailureAfterSuccessKeepsInformationButReportsOffline() async {
        let loader = MintDetailInfoLoader<String>()
        await loader.load { "saved" }
        await loader.load { throw URLError(.timedOut) }

        XCTAssertEqual(loader.info, "saved")
        XCTAssertNotNil(loader.errorMessage)
        XCTAssertEqual(loader.connection, .offline)
        XCTAssertFalse(loader.isLoading)
    }

    func testEmptyResponseFailsAndRetryClearsError() async {
        let loader = MintDetailInfoLoader<String>()
        await loader.load { nil }
        XCTAssertEqual(loader.errorMessage, "The mint did not respond.")
        XCTAssertEqual(loader.connection, .offline)

        await loader.load {
            XCTAssertTrue(loader.isLoading)
            XCTAssertEqual(loader.errorMessage, "The mint did not respond.")
            return "fresh"
        }
        XCTAssertEqual(loader.info, "fresh")
        XCTAssertNil(loader.errorMessage)
        XCTAssertEqual(loader.connection, .online)
    }

    func testSupersededCompletionCannotOverwriteNewerSuccess() async {
        let results: [Result<String?, Error>] = [
            .success("stale"), .failure(CancellationError()), .failure(URLError(.timedOut))
        ]
        for result in results {
            let loader = MintDetailInfoLoader<String>()
            let fetch = SuspendedFetch()
            let old = Task { await loader.load { try await fetch.value() } }
            await fulfillment(of: [fetch.started], timeout: 2)
            await loader.load { "fresh" }
            fetch.finish(with: result)
            await old.value

            XCTAssertEqual(loader.info, "fresh")
            XCTAssertNil(loader.errorMessage)
            XCTAssertEqual(loader.connection, .online)
        }
    }

    func testOlderCancellationCannotStopNewerLoadingIndicator() async {
        let loader = MintDetailInfoLoader<String>()
        let firstFetch = SuspendedFetch()
        let first = Task { await loader.load { try await firstFetch.value() } }
        await fulfillment(of: [firstFetch.started], timeout: 2)
        let secondFetch = SuspendedFetch()
        let second = Task { await loader.load { try await secondFetch.value() } }
        await fulfillment(of: [secondFetch.started], timeout: 2)

        first.cancel()
        firstFetch.finish(with: .failure(CancellationError()))
        await first.value
        XCTAssertTrue(loader.isLoading)
        XCTAssertNil(loader.errorMessage)

        secondFetch.finish(with: .success("fresh"))
        await second.value
        XCTAssertEqual(loader.connection, .online)
    }

    func testAlreadyCancelledTaskDoesNotStartFetch() async {
        let loader = MintDetailInfoLoader<String>()
        var didFetch = false
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await loader.load {
                didFetch = true
                return "unexpected"
            }
        }
        await task.value
        XCTAssertFalse(didFetch)
        XCTAssertEqual(loader.connection, .notChecked)
    }
}

/// Deliberately ignores cancellation, like a native call finishing after its view leaves.
@MainActor
private final class SuspendedFetch {
    let started = XCTestExpectation(description: "Mint info fetch started")
    private var continuation: CheckedContinuation<String?, Error>?

    func value() async throws -> String? {
        try await withCheckedThrowingContinuation {
            continuation = $0
            started.fulfill()
        }
    }

    func finish(with result: Result<String?, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
