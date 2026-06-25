import Foundation

struct TokenInfo {
    let amount: UInt64
    let mint: String
    let unit: String
    let memo: String?
    let proofCount: Int
    
    /// Parse a cashu token string
    static func parse(_ tokenString: String) -> TokenInfo? {
        TokenParser.tokenInfo(from: tokenString)
    }
}
