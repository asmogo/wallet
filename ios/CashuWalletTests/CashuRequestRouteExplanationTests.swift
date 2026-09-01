import XCTest
@testable import CashuWallet

final class CashuRequestRouteExplanationTests: XCTestCase {
    func testCompatibleMintRouteHasNoRedundantExplanation() {
        XCTAssertNil(CashuRequestRouteExplanation(state: .compatibleMint))
    }

    func testLightningFallbackNamesTheRailChange() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(state: .lightningFallback),
            .lightningFallback
        )
    }

    func testAddMintRecoveryNamesRequestedMintHost() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(
                state: .addRequestedMint(targetMintURL: "https://mint.example.com:3338/path")
            ),
            .addRequestedMint(target: "mint.example.com:3338")
        )
    }

    func testTopUpRecoveryNamesTargetMintHost() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(
                state: .topUpTargetMint(targetMintURL: "https://target.example.com/")
            ),
            .topUpTargetMint(target: "target.example.com")
        )
    }

    func testUnavailableRouteDoesNotInventAnExplanation() {
        XCTAssertNil(CashuRequestRouteExplanation(state: .unavailable))
    }

    func testMissingOrMalformedTargetKeepsGenericRecoveryExplanation() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(state: .addRequestedMint(targetMintURL: "  ")),
            .addRequestedMint(target: nil)
        )
        XCTAssertEqual(
            CashuRequestRouteExplanation(state: .topUpTargetMint(targetMintURL: "https://")),
            .topUpTargetMint(target: nil)
        )
    }
}

final class CashuRequestNostrReadinessTests: XCTestCase {
    private let publicKeyHex = String(repeating: "1", count: 64)
    private let privateKeyHex = String(repeating: "2", count: 64)

    func testReadyConfigurationKeepsOnlyNormalizedWebSocketRelays() {
        XCTAssertEqual(
            evaluate(
                relays: [
                    " https://not-a-relay.example ",
                    " wss://relay.example ",
                    "wss://relay.example",
                    "ws://localhost:7777",
                ]
            ),
            .ready(
                configuration: .init(
                    publicKeyHex: publicKeyHex,
                    relays: ["wss://relay.example", "ws://localhost:7777"]
                )
            )
        )
    }

    func testMissingKeyMaterialNamesExactNostrKeySetting() {
        XCTAssertEqual(
            CashuRequestNostrReadiness.evaluate(
                isIdentityInitialized: true,
                publicKeyHex: "not-a-key",
                privateKeyHex: nil,
                relays: ["wss://relay.example"],
                listenerEnabled: true
            ),
            .blocked(
                recoveryMessage:
                    "Your Nostr key isn't ready. Check Settings → Nostr → Nostr key, then try again.",
                requestConfiguration: nil
            )
        )
    }

    func testNoUsableRelayNamesExactRelaySetting() {
        XCTAssertEqual(
            evaluate(relays: ["", "https://relay.example", "wss://"]),
            .blocked(
                recoveryMessage:
                    "No usable Nostr relay is configured. Add a ws:// or wss:// relay in Settings → Nostr → Relays, then try again.",
                requestConfiguration: nil
            )
        )
    }

    func testDisabledListenerKeepsRequestBuildableAndNamesExactPrivacySetting() {
        XCTAssertEqual(
            evaluate(listenerEnabled: false),
            .blocked(
                recoveryMessage:
                    "Cashu Request listening is off. Turn on Settings → Privacy → Listen for payment requests, then try again.",
                requestConfiguration: .init(
                    publicKeyHex: publicKeyHex,
                    relays: ["wss://relay.example"]
                )
            )
        )
    }

    func testDisabledListenerUsesContextualDetailNotice() {
        XCTAssertEqual(
            evaluate(listenerEnabled: false).deliveryNotice,
            .init(
                title: "Payment requests are off",
                message: "You can share this request, but this wallet won't receive payments until you turn on Settings → Privacy → Listen for payment requests."
            )
        )
    }

    private func evaluate(
        relays: [String] = ["wss://relay.example"],
        listenerEnabled: Bool = true
    ) -> CashuRequestNostrReadiness {
        CashuRequestNostrReadiness.evaluate(
            isIdentityInitialized: true,
            publicKeyHex: publicKeyHex,
            privateKeyHex: privateKeyHex,
            relays: relays,
            listenerEnabled: listenerEnabled
        )
    }
}

@MainActor
final class CashuRequestListenerClientSlotTests: XCTestCase {
    private actor SuspendedInboxClient: CashuRequestInboxClient {
        private var startContinuation: CheckedContinuation<Void, Never>?
        private(set) var startCount = 0
        private(set) var stopCount = 0

        func start() async {
            startCount += 1
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }

        func stop() async {
            stopCount += 1
        }

        func releaseStart() {
            startContinuation?.resume()
            startContinuation = nil
        }

        func counts() -> (starts: Int, stops: Int) {
            (startCount, stopCount)
        }
    }

    private actor ImmediateInboxClient: CashuRequestInboxClient {
        private(set) var startCount = 0
        private(set) var stopCount = 0

        func start() async {
            startCount += 1
        }

        func stop() async {
            stopCount += 1
        }

        func counts() -> (starts: Int, stops: Int) {
            (startCount, stopCount)
        }
    }

    private actor SuspendedStopInboxClient: CashuRequestInboxClient {
        private var stopContinuation: CheckedContinuation<Void, Never>?
        private(set) var stopCount = 0

        func start() async {}

        func stop() async {
            stopCount += 1
            await withCheckedContinuation { continuation in
                stopContinuation = continuation
            }
        }

        func releaseStop() {
            stopContinuation?.resume()
            stopContinuation = nil
        }

        func stops() -> Int {
            stopCount
        }
    }

    func testConcurrentStartsCreateOnlyOneClient() async {
        let slot = CashuRequestListenerClientSlot()
        let client = SuspendedInboxClient()
        var factoryCalls = 0

        let firstStart = Task {
            await slot.start { _ in
                factoryCalls += 1
                return client
            }
        }
        await waitUntilStarted(client)

        let duplicateStarted = await slot.start { _ in
            factoryCalls += 1
            return SuspendedInboxClient()
        }

        XCTAssertFalse(duplicateStarted)
        XCTAssertEqual(factoryCalls, 1)
        await client.releaseStart()
        let firstResult = await firstStart.value
        XCTAssertTrue(firstResult)
        XCTAssertTrue(slot.isRunning)
        let counts = await client.counts()
        XCTAssertEqual(counts.starts, 1)
    }

    func testStopDuringStartCannotPublishStaleRunningState() async {
        let slot = CashuRequestListenerClientSlot()
        let client = SuspendedInboxClient()
        let start = Task { await slot.start { _ in client } }
        await waitUntilStarted(client)

        await slot.stop()
        await client.releaseStart()

        let startResult = await start.value
        XCTAssertFalse(startResult)
        XCTAssertFalse(slot.isRunning)
        let counts = await client.counts()
        XCTAssertEqual(counts.starts, 1)
        XCTAssertGreaterThanOrEqual(counts.stops, 1)
    }

    func testCancellationDuringStartRetiresCandidateAndAllowsRestart() async {
        let slot = CashuRequestListenerClientSlot()
        let client = SuspendedInboxClient()
        let start = Task { await slot.start { _ in client } }
        await waitUntilStarted(client)

        start.cancel()
        await client.releaseStart()

        let startResult = await start.value
        XCTAssertFalse(startResult)
        await waitUntilStopped(client)
        XCTAssertFalse(slot.isRunning)

        let replacement = ImmediateInboxClient()
        let replacementStarted = await slot.start { _ in replacement }
        XCTAssertTrue(replacementStarted)
        XCTAssertTrue(slot.isRunning)
    }

    func testWalletResetDuringStartStopsStaleClient() async {
        let slot = CashuRequestListenerClientSlot()
        let client = SuspendedInboxClient()
        let start = Task { await slot.start { _ in client } }
        await waitUntilStarted(client)

        slot.reset()
        await client.releaseStart()
        let startResult = await start.value
        XCTAssertFalse(startResult)
        await waitUntilStopped(client)

        XCTAssertFalse(slot.isRunning)
        let counts = await client.counts()
        XCTAssertEqual(counts.starts, 1)
        XCTAssertGreaterThanOrEqual(counts.stops, 1)
    }

    func testWalletResetInvalidatesOldCallbackGenerationAfterRestart() async {
        let slot = CashuRequestListenerClientSlot()
        let oldClient = ImmediateInboxClient()
        var oldGeneration: UInt?

        let oldStarted = await slot.start { generation in
            oldGeneration = generation
            return oldClient
        }
        XCTAssertTrue(oldStarted)
        let capturedOldGeneration = try? XCTUnwrap(oldGeneration)
        guard let capturedOldGeneration else { return }
        XCTAssertTrue(slot.owns(capturedOldGeneration))

        slot.reset()

        let newClient = ImmediateInboxClient()
        var newGeneration: UInt?
        let newStarted = await slot.start { generation in
            newGeneration = generation
            return newClient
        }
        XCTAssertTrue(newStarted)
        let capturedNewGeneration = try? XCTUnwrap(newGeneration)
        guard let capturedNewGeneration else { return }

        XCTAssertFalse(slot.owns(capturedOldGeneration))
        XCTAssertTrue(slot.owns(capturedNewGeneration))
        XCTAssertNotEqual(capturedOldGeneration, capturedNewGeneration)
    }

    func testRestartWaitsForRetiringClient() async {
        let slot = CashuRequestListenerClientSlot()
        let oldClient = SuspendedStopInboxClient()
        let oldStarted = await slot.start { _ in oldClient }
        XCTAssertTrue(oldStarted)

        let stop = Task { await slot.stop() }
        await waitUntilStopStarted(oldClient)

        let newClient = ImmediateInboxClient()
        var factoryCalls = 0
        let restart = Task {
            await slot.start { _ in
                factoryCalls += 1
                return newClient
            }
        }
        await Task.yield()

        XCTAssertEqual(factoryCalls, 0, "A replacement must wait for client retirement")
        await oldClient.releaseStop()
        await stop.value

        let restarted = await restart.value
        XCTAssertTrue(restarted)
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertTrue(slot.isRunning)
        let counts = await newClient.counts()
        XCTAssertEqual(counts.starts, 1)
    }

    func testCancelledRestartDoesNotStartAfterRetirement() async {
        let slot = CashuRequestListenerClientSlot()
        let oldClient = SuspendedStopInboxClient()
        let oldStarted = await slot.start { _ in oldClient }
        XCTAssertTrue(oldStarted)

        let stop = Task { await slot.stop() }
        await waitUntilStopStarted(oldClient)

        var factoryCalls = 0
        let restart = Task {
            await slot.start { _ in
                factoryCalls += 1
                return ImmediateInboxClient()
            }
        }
        await Task.yield()
        restart.cancel()
        await oldClient.releaseStop()

        await stop.value
        let restarted = await restart.value
        XCTAssertFalse(restarted)
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertFalse(slot.isRunning)
    }

    private func waitUntilStarted(_ client: SuspendedInboxClient) async {
        for _ in 0..<100 {
            if (await client.counts()).starts == 1 { return }
            await Task.yield()
        }
        XCTFail("Client start did not suspend in time")
    }

    private func waitUntilStopped(_ client: SuspendedInboxClient) async {
        for _ in 0..<100 {
            if (await client.counts()).stops >= 1 { return }
            await Task.yield()
        }
        XCTFail("Client stop did not run in time")
    }

    private func waitUntilStopStarted(_ client: SuspendedStopInboxClient) async {
        for _ in 0..<100 {
            if await client.stops() == 1 { return }
            await Task.yield()
        }
        XCTFail("Client stop did not suspend in time")
    }
}

@MainActor
final class CashuRequestListenerLifecycleSchedulerTests: XCTestCase {
    private actor InboxClient: CashuRequestInboxClient {
        private(set) var stopCount = 0

        func start() async {}

        func stop() async {
            stopCount += 1
        }

        func stops() -> Int {
            stopCount
        }
    }

    private actor SuspendedStartInboxClient: CashuRequestInboxClient {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var startCount = 0

        func start() async {
            startCount += 1
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func stop() async {}

        func releaseStart() {
            continuation?.resume()
            continuation = nil
        }

        func starts() -> Int {
            startCount
        }
    }

    func testLatestForegroundIntentWinsBeforeBackgroundTaskStarts() async {
        let slot = CashuRequestListenerClientSlot()
        let scheduler = CashuRequestListenerLifecycleScheduler()
        let existingClient = InboxClient()
        let existingStarted = await slot.start { _ in existingClient }
        XCTAssertTrue(existingStarted)

        let background = scheduler.submit(.stop) {
            await slot.stop()
        }
        var replacementFactoryCalls = 0
        let foreground = scheduler.submit(.start) {
            _ = await slot.start { _ in
                replacementFactoryCalls += 1
                return InboxClient()
            }
        }

        await background.value
        await foreground.value

        XCTAssertTrue(slot.isRunning)
        let stopCount = await existingClient.stops()
        XCTAssertEqual(stopCount, 0)
        XCTAssertEqual(replacementFactoryCalls, 0)
    }

    func testLatestBackgroundIntentCancelsQueuedForegroundStart() async {
        let slot = CashuRequestListenerClientSlot()
        let scheduler = CashuRequestListenerLifecycleScheduler()
        let existingClient = InboxClient()
        let existingStarted = await slot.start { _ in existingClient }
        XCTAssertTrue(existingStarted)

        let foreground = scheduler.submit(.start) {
            _ = await slot.start { _ in InboxClient() }
        }
        let background = scheduler.submit(.stop) {
            await slot.stop()
        }

        await foreground.value
        await background.value

        XCTAssertFalse(slot.isRunning)
        let stopCount = await existingClient.stops()
        XCTAssertEqual(stopCount, 1)
    }

    func testDuplicateStartIntentSharesInFlightStart() async {
        let slot = CashuRequestListenerClientSlot()
        let scheduler = CashuRequestListenerLifecycleScheduler()
        let client = SuspendedStartInboxClient()
        var factoryCalls = 0

        let first = scheduler.submit(.start) {
            _ = await slot.start { _ in
                factoryCalls += 1
                return client
            }
        }
        for _ in 0..<100 {
            if await client.starts() == 1 { break }
            await Task.yield()
        }

        let duplicate = scheduler.submit(.start) {
            _ = await slot.start { _ in
                factoryCalls += 1
                return SuspendedStartInboxClient()
            }
        }
        await Task.yield()
        XCTAssertEqual(factoryCalls, 1)

        await client.releaseStart()
        await first.value
        await duplicate.value
        XCTAssertTrue(slot.isRunning)
    }
}

@MainActor
final class ProcessedNIP17EventTrackerTests: XCTestCase {
    func testTransientEventCanRetryButTerminalEventPersists() {
        var stored: [String] = []
        let tracker = ProcessedNIP17EventTracker(
            load: { stored },
            save: { stored = $0 }
        )
        tracker.reload()

        XCTAssertTrue(tracker.begin("retryable"))
        tracker.finish("retryable", terminalOutcome: false)
        XCTAssertTrue(tracker.begin("retryable"))

        tracker.finish("retryable", terminalOutcome: true)
        XCTAssertEqual(stored, ["retryable"])
        XCTAssertFalse(tracker.begin("retryable"))

        let reloaded = ProcessedNIP17EventTracker(
            load: { stored },
            save: { stored = $0 }
        )
        reloaded.reload()
        XCTAssertFalse(reloaded.begin("retryable"))
    }

    func testConcurrentDuplicateIsSuppressedAndHistoryIsBounded() {
        var stored: [String] = []
        let tracker = ProcessedNIP17EventTracker(
            load: { stored },
            save: { stored = $0 },
            maxProcessedIds: 2
        )
        tracker.reload()

        XCTAssertTrue(tracker.begin("duplicate"))
        XCTAssertFalse(tracker.begin("duplicate"))
        tracker.finish("duplicate", terminalOutcome: true)

        XCTAssertTrue(tracker.begin("second"))
        tracker.finish("second", terminalOutcome: true)
        XCTAssertTrue(tracker.begin("third"))
        tracker.finish("third", terminalOutcome: true)

        XCTAssertEqual(stored, ["second", "third"])
        XCTAssertTrue(tracker.begin("duplicate"), "Evicted events may be reconsidered")
        tracker.finish("duplicate", terminalOutcome: false)
    }
}

@MainActor
final class CashuRequestListenerWorkGateTests: XCTestCase {
    private actor CompletionFlag {
        private var completed = false

        func markCompleted() {
            completed = true
        }

        func isCompleted() -> Bool {
            completed
        }
    }

    func testSuspensionRejectsNewWorkAndWaitsForEveryExistingLease() async {
        let gate = CashuRequestListenerWorkGate()
        let drainCompleted = CompletionFlag()

        XCTAssertTrue(gate.begin())
        XCTAssertTrue(gate.begin())
        XCTAssertEqual(gate.activeWorkCount, 2)

        gate.suspend()
        XCTAssertFalse(gate.acceptsNewWork)
        XCTAssertFalse(gate.begin(), "A wallet boundary must reject late listener work")

        let drain = Task { @MainActor in
            await gate.waitUntilDrained()
            await drainCompleted.markCompleted()
        }
        await Task.yield()
        let completedBeforeRelease = await drainCompleted.isCompleted()
        XCTAssertFalse(completedBeforeRelease)

        gate.end()
        await Task.yield()
        XCTAssertEqual(gate.activeWorkCount, 1)
        let completedAfterOneRelease = await drainCompleted.isCompleted()
        XCTAssertFalse(completedAfterOneRelease, "One completed receive must not release another")

        gate.end()
        await drain.value
        XCTAssertEqual(gate.activeWorkCount, 0)
        let completedAfterDrain = await drainCompleted.isCompleted()
        XCTAssertTrue(completedAfterDrain)
    }

    func testGateReopensOnlyAfterExplicitResume() async {
        let gate = CashuRequestListenerWorkGate()

        gate.suspend()
        await gate.waitUntilDrained()
        XCTAssertFalse(gate.begin())

        gate.resume()
        XCTAssertTrue(gate.begin())
        gate.end()
    }
}
