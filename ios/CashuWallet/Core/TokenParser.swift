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
              let mint = try? token.mintUrl().url else {
            return nil
        }

        // IDv2 keysets may not be resolvable through `proofsSimple()` without
        // a keyset list. The token's aggregate value and unit remain available,
        // so keep returning useful metadata when proof expansion fails.
        let proofs = (try? token.proofsSimple()) ?? []
        let amount = (try? token.value().value)
            ?? proofs.reduce(UInt64(0)) { $0 + $1.amount.value }
        return TokenInfo(
            amount: amount,
            mint: mint,
            unit: PaymentRequestDecoder.unitDescription(token.unit() ?? .sat),
            memo: token.memo(),
            proofCount: proofs.count
        )
    }

    /// Decode only the token's mint URL — enough to scope a NUT-07 spent
    /// check without expanding proofs (`proofsSimple()` can fail for IDv2
    /// keysets even though the token itself is valid).
    static func mintUrl(from tokenString: String) -> String? {
        guard let normalized = normalizedToken(from: tokenString),
              let token = try? Token.decode(encodedToken: normalized),
              let mint = try? token.mintUrl().url else {
            return nil
        }
        return mint
    }

    /// Decode only the token's mint account unit. Unlike `tokenInfo(from:)`,
    /// this deliberately does not expand proofs: `proofsSimple()` can fail for
    /// IDv2 keysets even though the token itself and its unit are valid.
    static func unit(from tokenString: String) -> String? {
        guard let normalized = normalizedToken(from: tokenString),
              let token = try? Token.decode(encodedToken: normalized) else {
            return nil
        }
        return PaymentRequestDecoder.unitDescription(token.unit() ?? .sat)
    }

    private static func stripCashuScheme(from token: String) -> String {
        let prefixes = ["cashu://", "cashu:"]
        for prefix in prefixes where token.lowercased().hasPrefix(prefix) {
            return String(token.dropFirst(prefix.count))
        }
        return token
    }
}
