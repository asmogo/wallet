#if DEBUG
import Foundation
import Cdk

/// Replaces only the external address-service transport in UI integration mode.
/// Production connection, settings, and lifecycle code still execute normally.
@MainActor
final class UITestNPCClient: NpubCashClientProtocol {
    private var mintURL: String?

    func getQuotes(since: UInt64?) async throws -> [NpubCashQuote] { [] }
    func getMissingQuotes(quoteIds: [String]) async throws -> [NpubCashQuote] { [] }
    func getUserInfo() async throws -> NpubCashUserResponse {
        NpubCashUserResponse(error: false, pubkey: "", mintUrl: mintURL, lockQuote: false)
    }
    func setMintUrl(mintUrl: String) async throws -> NpubCashUserResponse {
        mintURL = mintUrl
        return try await getUserInfo()
    }
    func setQuoteLocking(lockQuotes: Bool) async throws -> NpubCashUserResponse {
        NpubCashUserResponse(error: false, pubkey: "", mintUrl: mintURL, lockQuote: lockQuotes)
    }
}
#endif
