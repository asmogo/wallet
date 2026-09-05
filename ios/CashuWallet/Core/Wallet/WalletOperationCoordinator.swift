import CryptoKit
import Cdk
import Foundation
import UIKit

/// The shared execution lane for CDK calls that use the wallet repository and
/// SQLite database. `@MainActor` is not sufficient here: an actor can accept a
/// second operation whenever the first one suspends at an `await`.
///
/// This coordinator records ownership explicitly, so actor reentrancy cannot
/// admit a second operation until the first native future has actually
/// returned. Cancellation never force-releases an executing lease.
actor WalletOperationCoordinator {
    enum Kind: String, Sendable {
        case addMint
        case removeMint
        case balance
        case feeEstimate
        case history
        case melt
        case meltQuote
        case mint
        case mintInfo
        case mintQuote
        case pendingMeltPoll
        case pendingTokenCheck
        case quotePoll
        case receive
        case receiveFee
        case recovery
        case restore
        case send
        case tokenStatus
    }

    enum Priority: Int, Sendable {
        case maintenance = 0
        case userInitiated = 10
        case recovery = 20
    }

    enum FailureOutcome: String, Sendable {
        case definiteFailure = "definite-failure"
        case ambiguousFailure = "ambiguous-failure"
    }

    struct Snapshot: Sendable {
        let activeKind: Kind?
        let waitingCount: Int
        let waitingUserOperationCount: Int
    }

    private struct Request: Sendable {
        let id: UUID
        let kind: Kind
        let priority: Priority
        let sequence: UInt64
    }

    private struct Lease: Sendable {
        let request: Request
        let acquiredAt: UInt64
    }

    private struct Waiter {
        let request: Request
        let continuation: CheckedContinuation<Lease, Error>
    }

    private var activeLease: Lease?
    private var waiters: [Waiter] = []
    private var nextSequence: UInt64 = 0
    private let watchdogThresholdNanoseconds: UInt64

    init(watchdogThreshold: TimeInterval = 30) {
        watchdogThresholdNanoseconds = UInt64(max(0, watchdogThreshold) * 1_000_000_000)
    }

    /// Queue an operation until the repository is exclusively available.
    /// Higher-priority work is selected first; ordering is FIFO within a tier.
    nonisolated func perform<T>(
        kind: Kind,
        priority: Priority = .userInitiated,
        resourceID: String? = nil,
        protectsBackgroundExecution: Bool = false,
        defaultFailureOutcome: FailureOutcome = .definiteFailure,
        operation: () async throws -> T
    ) async throws -> T {
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        let lease = try await acquire(kind: kind, priority: priority)

        do {
            try Task.checkCancellation()
        } catch {
            await release(lease)
            throw error
        }

        return try await execute(
            lease: lease,
            requestedAt: requestedAt,
            resourceID: resourceID,
            protectsBackgroundExecution: protectsBackgroundExecution,
            defaultFailureOutcome: defaultFailureOutcome,
            operation: operation
        )
    }

    /// Run passive maintenance only when the lane is completely idle. Polling
    /// never queues behind a payment and cannot become stale work that delays a
    /// later user action.
    @discardableResult
    nonisolated func performIfIdle(
        kind: Kind,
        resourceID: String? = nil,
        operation: () async throws -> Void
    ) async throws -> Bool {
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        guard let lease = await tryAcquire(kind: kind, priority: .maintenance) else {
            Self.logSkipped(kind: kind)
            return false
        }

        do {
            try Task.checkCancellation()
        } catch {
            await release(lease)
            throw error
        }

        _ = try await execute(
            lease: lease,
            requestedAt: requestedAt,
            resourceID: resourceID,
            protectsBackgroundExecution: false,
            defaultFailureOutcome: .definiteFailure,
            operation: operation
        )
        return true
    }

    func snapshot() -> Snapshot {
        Snapshot(
            activeKind: activeLease?.request.kind,
            waitingCount: waiters.count,
            waitingUserOperationCount: waiters.filter { $0.request.priority != .maintenance }.count
        )
    }

    func hasWaitingUserOperation() -> Bool {
        waiters.contains { $0.request.priority != .maintenance }
    }

    /// Called with the wallet-boundary lease held. Queued closures may retain
    /// the previous repository and must not run after its files are replaced.
    func cancelPendingOperations() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    private func acquire(kind: Kind, priority: Priority) async throws -> Lease {
        let request = makeRequest(kind: kind, priority: priority)
        if activeLease == nil {
            let lease = Lease(request: request, acquiredAt: DispatchTime.now().uptimeNanoseconds)
            activeLease = lease
            return lease
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(request: request, continuation: continuation))
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            Task { await self.cancelWaiter(id: request.id) }
        }
    }

    private func tryAcquire(kind: Kind, priority: Priority) -> Lease? {
        guard activeLease == nil, waiters.isEmpty else { return nil }
        let request = makeRequest(kind: kind, priority: priority)
        let lease = Lease(request: request, acquiredAt: DispatchTime.now().uptimeNanoseconds)
        activeLease = lease
        return lease
    }

    private func makeRequest(kind: Kind, priority: Priority) -> Request {
        defer { nextSequence &+= 1 }
        return Request(
            id: UUID(),
            kind: kind,
            priority: priority,
            sequence: nextSequence
        )
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.request.id == id }) else {
            // The lease may already have been granted. The resumed task checks
            // cancellation before entering the native operation and releases it.
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release(_ lease: Lease) {
        guard activeLease?.request.id == lease.request.id else {
            AppLogger.wallet.fault(
                "wallet-op invalid release correlation=\(Self.correlationID(for: lease.request.id), privacy: .public) kind=\(lease.request.kind.rawValue, privacy: .public)"
            )
            return
        }

        activeLease = nil
        guard let index = nextWaiterIndex() else { return }
        let waiter = waiters.remove(at: index)
        let nextLease = Lease(
            request: waiter.request,
            acquiredAt: DispatchTime.now().uptimeNanoseconds
        )
        activeLease = nextLease
        waiter.continuation.resume(returning: nextLease)
    }

    private func nextWaiterIndex() -> Int? {
        waiters.indices.max { left, right in
            let lhs = waiters[left].request
            let rhs = waiters[right].request
            if lhs.priority.rawValue == rhs.priority.rawValue {
                // `max` should choose the older (smaller sequence) request.
                return lhs.sequence > rhs.sequence
            }
            return lhs.priority.rawValue < rhs.priority.rawValue
        }
    }

    private nonisolated func execute<T>(
        lease: Lease,
        requestedAt: UInt64,
        resourceID: String?,
        protectsBackgroundExecution: Bool,
        defaultFailureOutcome: FailureOutcome,
        operation: () async throws -> T
    ) async throws -> T {
        let correlationID = Self.correlationID(for: lease.request.id)
        let resourceHash = resourceID.map(Self.privacySafeIdentifier) ?? "none"
        let waitMilliseconds = Self.milliseconds(from: requestedAt, to: lease.acquiredAt)
        let appState = await MainActor.run { WalletApplicationState.current }
        let executionStartedAt = DispatchTime.now().uptimeNanoseconds
        let backgroundLease = await MainActor.run {
            protectsBackgroundExecution
                ? WalletBackgroundExecutionLease(kind: lease.request.kind, correlationID: correlationID)
                : nil
        }

        AppLogger.wallet.info(
            "wallet-op begin correlation=\(correlationID, privacy: .public) kind=\(lease.request.kind.rawValue, privacy: .public) resource=\(resourceHash, privacy: .public) wait_ms=\(waitMilliseconds, privacy: .public) app_state=\(appState, privacy: .public) cancelled=\(Task.isCancelled, privacy: .public)"
        )

        let watchdog = makeWatchdog(
            kind: lease.request.kind,
            correlationID: correlationID,
            executionStartedAt: executionStartedAt
        )

        do {
            let value = try await operation()
            watchdog?.cancel()
            await backgroundLease?.end()
            let duration = Self.milliseconds(
                from: executionStartedAt,
                to: DispatchTime.now().uptimeNanoseconds
            )
            AppLogger.wallet.info(
                "wallet-op end correlation=\(correlationID, privacy: .public) kind=\(lease.request.kind.rawValue, privacy: .public) outcome=success execution_ms=\(duration, privacy: .public) cancelled=\(Task.isCancelled, privacy: .public)"
            )
            await release(lease)
            return value
        } catch {
            watchdog?.cancel()
            await backgroundLease?.end()
            let duration = Self.milliseconds(
                from: executionStartedAt,
                to: DispatchTime.now().uptimeNanoseconds
            )
            let outcome: String
            if error is CancellationError {
                outcome = "cancellation"
            } else if let classified = error as? WalletOperationOutcomeError {
                outcome = classified.walletOperationFailureOutcome.rawValue
            } else {
                outcome = defaultFailureOutcome.rawValue
            }
            AppLogger.wallet.error(
                "wallet-op end correlation=\(correlationID, privacy: .public) kind=\(lease.request.kind.rawValue, privacy: .public) outcome=\(outcome, privacy: .public) execution_ms=\(duration, privacy: .public) cancelled=\(Task.isCancelled, privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            await release(lease)
            throw error
        }
    }

    private nonisolated func makeWatchdog(
        kind: Kind,
        correlationID: String,
        executionStartedAt: UInt64
    ) -> Task<Void, Never>? {
        guard watchdogThresholdNanoseconds > 0 else { return nil }
        let delay = watchdogThresholdNanoseconds
        return Task.detached(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            let elapsed = Self.milliseconds(
                from: executionStartedAt,
                to: DispatchTime.now().uptimeNanoseconds
            )
            AppLogger.wallet.warning(
                "wallet-op watchdog correlation=\(correlationID, privacy: .public) kind=\(kind.rawValue, privacy: .public) execution_ms=\(elapsed, privacy: .public); lease remains held"
            )
        }
    }

    private nonisolated static func logSkipped(kind: Kind) {
        AppLogger.wallet.debug(
            "wallet-op skipped kind=\(kind.rawValue, privacy: .public) reason=busy"
        )
    }

    private nonisolated static func correlationID(for id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    nonisolated static func privacySafeIdentifier(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func milliseconds(from start: UInt64, to end: UInt64) -> UInt64 {
        guard end >= start else { return 0 }
        return (end - start) / 1_000_000
    }
}

extension WalletManager {
    /// Read-only state capture at a failed-operation boundary. This method is
    /// called while the coordinator lease is still held so the snapshot cannot
    /// race a second CDK writer. It logs counts and hashes only—never tokens,
    /// invoices, preimages, URLs, or saga JSON.
    func captureWalletFailureDiagnostics(
        kind: WalletOperationCoordinator.Kind,
        operationID: String? = nil,
        quoteID: String? = nil
    ) async {
        var incompleteSagaCount = -1
        var knownSagaExists = false
        var reservedProofCount = -1
        var quoteReserved = false
        var quoteOperationHash = "none"

        if let db {
            incompleteSagaCount = (try? await db.getIncompleteSagas().count) ?? -1
            if let operationID {
                knownSagaExists = ((try? await db.getSaga(id: operationID)) ?? nil) != nil
                reservedProofCount = (try? await db.getReservedProofs(operationId: operationID).count) ?? -1
            }
            if let quoteID,
               let quote = try? await db.getMeltQuote(quoteId: quoteID) {
                quoteReserved = quote.usedByOperation != nil
                if let usedByOperation = quote.usedByOperation {
                    quoteOperationHash = WalletOperationCoordinator.privacySafeIdentifier(usedByOperation)
                }
            }
        }

        var inspectedWalletCount = 0
        var totalReservedBalance: UInt64 = 0
        var pendingSendCount = 0
        if let walletRepository {
            for mintURL in trackedMintUrlsForWalletAccess() {
                guard let wallet = try? await walletRepository.getWallet(
                    mintUrl: MintUrl(url: mintURL),
                    unit: .sat
                ) else { continue }
                inspectedWalletCount += 1
                if let reserved = try? await wallet.totalReservedBalance().value {
                    totalReservedBalance &+= reserved
                }
                pendingSendCount += (try? await wallet.getPendingSends().count) ?? 0
            }
        }

        let operationHash = operationID.map(WalletOperationCoordinator.privacySafeIdentifier) ?? "none"
        let quoteHash = quoteID.map(WalletOperationCoordinator.privacySafeIdentifier) ?? "none"
        AppLogger.wallet.info(
            "wallet-op failure-state kind=\(kind.rawValue, privacy: .public) operation=\(operationHash, privacy: .public) quote=\(quoteHash, privacy: .public) incomplete_sagas=\(incompleteSagaCount, privacy: .public) known_saga=\(knownSagaExists, privacy: .public) quote_reserved=\(quoteReserved, privacy: .public) quote_operation=\(quoteOperationHash, privacy: .public) reserved_proofs=\(reservedProofCount, privacy: .public) reserved_balance=\(totalReservedBalance, privacy: .public) pending_sends=\(pendingSendCount, privacy: .public) wallets=\(inspectedWalletCount, privacy: .public)"
        )
    }

    /// Ask CDK to reconcile any saga left by a failed interactive operation.
    /// Call only while the shared operation lease is held. Recovery is
    /// status-aware and may deliberately leave an externally ambiguous saga in
    /// place; this method never releases proofs, quotes, or saga rows directly.
    func recoverWalletStateAfterFailureAssumingWalletOperationLease(
        kind: WalletOperationCoordinator.Kind,
        preferredMintURL: String?,
        unit: Cdk.CurrencyUnit = .sat
    ) async {
        guard let walletRepository else { return }

        let mintURLs: [String]
        if let preferredMintURL, !preferredMintURL.isEmpty {
            mintURLs = [preferredMintURL]
        } else {
            mintURLs = trackedMintUrlsForWalletAccess()
        }

        for mintURL in mintURLs {
            do {
                let wallet = try await walletRepository.getWallet(
                    mintUrl: MintUrl(url: mintURL),
                    unit: unit
                )
                let sagasBefore = (try? await db?.getIncompleteSagas().count) ?? -1
                let reservedBefore = (try? await wallet.totalReservedBalance().value) ?? UInt64.max
                let pendingBefore = (try? await wallet.getPendingSends().count) ?? -1

                // A successful zero count is positive evidence that this
                // operation did not leave a recoverable saga. A failed read
                // (-1) still warrants a best-effort CDK recovery attempt.
                guard sagasBefore != 0 else {
                    AppLogger.wallet.info(
                        "wallet-op foreground recovery kind=\(kind.rawValue, privacy: .public) resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintURL), privacy: .public) skipped=no-incomplete-sagas reserved_before=\(reservedBefore, privacy: .public) pending_before=\(pendingBefore, privacy: .public)"
                    )
                    continue
                }

                let report = try await wallet.recoverIncompleteSagas()
                let sagasAfter = (try? await db?.getIncompleteSagas().count) ?? -1
                let reservedAfter = (try? await wallet.totalReservedBalance().value) ?? UInt64.max
                let pendingAfter = (try? await wallet.getPendingSends().count) ?? -1
                AppLogger.wallet.info(
                    "wallet-op foreground recovery kind=\(kind.rawValue, privacy: .public) resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintURL), privacy: .public) recovered=\(report.recovered, privacy: .public) compensated=\(report.compensated, privacy: .public) skipped=\(report.skipped, privacy: .public) failed=\(report.failed, privacy: .public) sagas_before=\(sagasBefore, privacy: .public) sagas_after=\(sagasAfter, privacy: .public) reserved_before=\(reservedBefore, privacy: .public) reserved_after=\(reservedAfter, privacy: .public) pending_before=\(pendingBefore, privacy: .public) pending_after=\(pendingAfter, privacy: .public)"
                )
            } catch {
                AppLogger.wallet.warning(
                    "wallet-op foreground recovery failed kind=\(kind.rawValue, privacy: .public) resource=\(WalletOperationCoordinator.privacySafeIdentifier(mintURL), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }
    }
}

/// Errors can override the coordinator's conservative default when recovery
/// has established whether a failed money movement is terminal or ambiguous.
protocol WalletOperationOutcomeError: Error {
    var walletOperationFailureOutcome: WalletOperationCoordinator.FailureOutcome { get }
}

@MainActor
private enum WalletApplicationState {
    static var current: String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}

/// Extends the time iOS gives a money-moving native future after the app moves
/// to the background. Expiration ends only the OS assertion; it never unlocks
/// the coordinator or pretends the CDK operation was cancelled.
@MainActor
private final class WalletBackgroundExecutionLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let kind: WalletOperationCoordinator.Kind
    private let correlationID: String

    init(kind: WalletOperationCoordinator.Kind, correlationID: String) {
        self.kind = kind
        self.correlationID = correlationID
        identifier = UIApplication.shared.beginBackgroundTask(
            withName: "wallet.\(kind.rawValue)"
        ) { [weak self] in
            self?.expire()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }

    private func expire() {
        AppLogger.wallet.warning(
            "wallet-op background time expired correlation=\(self.correlationID, privacy: .public) kind=\(self.kind.rawValue, privacy: .public); native operation remains serialized"
        )
        end()
    }
}
