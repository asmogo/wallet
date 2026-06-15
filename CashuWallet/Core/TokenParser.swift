import Foundation
import Cdk

enum TokenParser {
    static func normalizedToken(from rawToken: String) -> String? {
        let token = stripCashuScheme(from: rawToken.trimmingCharacters(in: .whitespacesAndNewlines))
        guard isCashuDeepLinkToken(token) else { return nil }
        return token
    }

    static func isCashuToken(_ token: String) -> Bool {
        normalizedToken(from: token) != nil
    }

    static func isCashuDeepLinkToken(_ token: String) -> Bool {
        let lowercased = token.lowercased()
        return lowercased.hasPrefix("cashua") || lowercased.hasPrefix("cashub")
    }

    static func tokenInfo(from tokenString: String) -> TokenInfo? {
        guard let normalized = normalizedToken(from: tokenString),
              let token = try? Token.decode(encodedToken: normalized),
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

    private static func stripCashuScheme(from token: String) -> String {
        let prefixes = ["cashu://", "cashu:"]
        for prefix in prefixes where token.lowercased().hasPrefix(prefix) {
            return String(token.dropFirst(prefix.count))
        }
        return token
    }
}
