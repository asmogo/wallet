import Cdk
import Foundation

enum MintQuoteRecovery {
    /// Only CDK may resolve an interrupted mint. Keeping its saga intact lets
    /// recovery retrieve the original outputs after a lost mint response.
    static func reconcile(
        quote: MintQuote,
        recover: () async throws -> Void,
        reload: () async throws -> MintQuote?
    ) async throws -> UInt64 {
        try await recover()
        guard let refreshed = try await reload(),
              refreshed.usedByOperation == nil else {
            throw WalletError.networkError(
                "This receive is still being recovered. Check History again before retrying."
            )
        }
        return refreshed.amountIssued.value - min(quote.amountIssued.value, refreshed.amountIssued.value)
    }
}
