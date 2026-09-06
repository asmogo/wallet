import Foundation

/// The visible payment code owns this loop. Cancelling its view task releases
/// the focus, allowing ordinary wallet maintenance to resume.
@MainActor
final class FocusedMintQuoteMonitor {
    private var sessions: Set<UUID> = []
    var isActive: Bool { !sessions.isEmpty }

    func monitor(
        quoteID: String,
        refresh: (String) async -> MintQuoteInfo?,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async {
        guard !Task.isCancelled else { return }
        let session = UUID()
        sessions.insert(session)
        defer { sessions.remove(session) }

        while !Task.isCancelled {
            // Direct reconciliation bypasses the passive batch/age schedule,
            // but still respects persisted failure backoff in the reconciler.
            let quote = await refresh(quoteID)
            guard !Task.isCancelled else { return }
            if let quote, quote.paymentMethod != .bolt12,
               quote.hasSettledPayment ||
                (quote.paymentMethod == .bolt11 && quote.isExpired && quote.mintableAmount == 0) {
                return
            }
            do {
                try await sleep(quote?.paymentMethod == .onchain ? .seconds(10) : .seconds(2))
            } catch {
                return
            }
        }
    }
}
