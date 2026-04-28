import Foundation
import CashuDevKit

enum TokenParser {
    static func normalizedToken(from rawToken: String) -> String? {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCashuToken(token) else { return nil }
        return token
    }

    static func isCashuToken(_ token: String) -> Bool {
        token.lowercased().hasPrefix("cashu")
    }

    static func isCashuDeepLinkToken(_ token: String) -> Bool {
        let lowercased = token.lowercased()
        return lowercased.hasPrefix("cashua") || lowercased.hasPrefix("cashub")
    }

    static func tokenInfo(from tokenString: String) -> TokenInfo? {
        guard isCashuToken(tokenString),
              let token = try? Token.decode(encodedToken: tokenString),
              let mint = try? token.mintUrl().url,
              let proofs = try? token.proofsSimple() else {
            return nil
        }

        let amount = proofs.reduce(UInt64(0)) { $0 + $1.amount.value }
        return TokenInfo(
            amount: amount,
            mint: mint,
            unit: "sat",
            memo: token.memo(),
            proofCount: proofs.count
        )
    }
}
