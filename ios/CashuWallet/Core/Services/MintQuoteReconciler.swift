import Foundation

/// Runs under WalletManager's repository lease. Keeping network checks inside
/// this operation makes recovery, retry deadlines, and issuance one workflow.
@MainActor
struct MintQuoteReconciler {
    private enum ReconciliationError: Error { case noIssuanceProgress }

    var storedQuote: (String) async -> MintQuoteInfo?
    var checkQuote: (String) async throws -> MintQuoteInfo
    var mintQuote: (String) async throws -> UInt64
    var schedule: (String) -> MintQuoteScheduleRecord?
    var observed: (MintQuoteInfo) -> Void
    var failed: (String, MintQuoteInfo?) -> MintQuoteRetryStatus
    var logFailure: (String, Error) -> Void
    var now: () -> Date = Date.init

    func reconcile(quoteID: String, force: Bool = false) async -> MintQuoteReconciliationResult? {
        let cached = await storedQuote(quoteID)
        guard !Task.isCancelled else { return nil }
        let record = schedule(quoteID)
        guard MintQuoteSchedulePolicy.shouldAttempt(record: record, now: now(), force: force) else {
            return cached.map {
                MintQuoteReconciliationResult(
                    observed: $0,
                    retryStatus: record.map(MintQuoteSchedulePolicy.retryStatus) ?? MintQuoteRetryStatus()
                )
            }
        }

        let checked: MintQuoteInfo
        do {
            checked = try await checkQuote(quoteID)
        } catch is CancellationError {
            return nil
        } catch {
            logFailure(quoteID, error)
            let local = await storedQuote(quoteID) ?? cached
            let retryStatus = failed(quoteID, local)
            return local.map { MintQuoteReconciliationResult(observed: $0, retryStatus: retryStatus) }
        }

        guard checked.mintableAmount > 0 else {
            observed(checked)
            return MintQuoteReconciliationResult(
                observed: checked,
                issuedBeforeCheck: cached?.amountIssued
            )
        }

        var mintedAmount: UInt64 = 0
        var mintError: Error?
        do {
            mintedAmount = try await mintQuote(quoteID)
        } catch is CancellationError {
            return nil
        } catch {
            mintError = error
        }

        let verified: MintQuoteInfo?
        do {
            verified = try await checkQuote(quoteID)
        } catch is CancellationError {
            return nil
        } catch {
            verified = nil
        }

        let result = MintQuoteReconciliationResult(
            observed: checked,
            mintedAmount: mintedAmount,
            verified: verified,
            issuedBeforeCheck: cached?.amountIssued
        )
        if result.remainingAmount > 0 {
            logFailure(quoteID, mintError ?? ReconciliationError.noIssuanceProgress)
            return MintQuoteReconciliationResult(
                observed: checked,
                mintedAmount: mintedAmount,
                verified: verified,
                issuedBeforeCheck: cached?.amountIssued,
                retryStatus: failed(quoteID, result.quote)
            )
        }

        observed(result.quote)
        return result
    }
}
