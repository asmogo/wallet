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

/// Resolve the local pending-token record behind a History row.
///
/// CDK transaction IDs can replace the local token ID during History merging,
/// so the encoded token is the stable first choice and the ID is a legacy
/// fallback.
func pendingSentTokenFor(
    transaction: WalletTransaction,
    pendingTokens: [PendingToken]
) -> PendingToken? {
    guard transaction.type == .outgoing,
          transaction.kind == .ecash,
          transaction.status == .pending,
          transaction.isPendingToken else {
        return nil
    }

    if let token = transaction.token,
       let matchingToken = pendingTokens.first(where: { $0.token == token }) {
        return matchingToken
    }

    return pendingTokens.first(where: { $0.tokenId == transaction.id })
}

func shouldOfferManualClaimCheck(
    automaticChecksEnabled: Bool,
    pendingToken: PendingToken?
) -> Bool {
    !automaticChecksEnabled && pendingToken != nil
}
