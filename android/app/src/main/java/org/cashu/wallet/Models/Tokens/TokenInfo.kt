package org.cashu.wallet.Models

import kotlinx.serialization.Serializable
import org.cashu.wallet.Core.TokenParser

@Serializable
data class TokenInfo(
    val amount: Long,
    val mint: String,
    val unit: String,
    val memo: String?,
    val proofCount: Int,
) {
    companion object {
        fun parse(tokenString: String): TokenInfo? = TokenParser.tokenInfo(tokenString)
    }
}
