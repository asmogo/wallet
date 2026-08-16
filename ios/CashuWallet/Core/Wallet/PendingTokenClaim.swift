import Foundation

/// Result of a user-initiated spent-status probe.
///
/// A successful mint response that reports unspent proofs is distinct from a
/// transport or wallet failure so the UI can acknowledge the completed check
/// without hiding a retryable error.
enum PendingTokenClaimCheckResult {
    case claimed
    case notClaimed
    case failed(WalletMessage)
}

/// Run one status probe while preserving structured task cancellation.
func runPendingTokenClaimCheck(
    check: () async throws -> Bool
) async throws -> PendingTokenClaimCheckResult {
    do {
        return try await check() ? .claimed : .notClaimed
    } catch {
        if error is CancellationError || Task.isCancelled {
            throw CancellationError()
        }
        return .failed(error.walletMessage)
    }
}

/// A History row is a pending sent token when CDK reports the outgoing ecash
/// transaction as still pending (unclaimed). CDK 0.18 owns this lifecycle
/// state; the attached token string lets the detail view re-present it.
func isPendingSentToken(_ transaction: WalletTransaction) -> Bool {
    transaction.type == .outgoing
        && transaction.kind == .ecash
        && transaction.status == .pending
        && transaction.token != nil
}

func shouldOfferManualClaimCheck(
    automaticChecksEnabled: Bool,
    transaction: WalletTransaction
) -> Bool {
    !automaticChecksEnabled && isPendingSentToken(transaction)
}
