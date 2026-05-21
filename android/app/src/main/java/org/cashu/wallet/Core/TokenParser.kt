package org.cashu.wallet.Core

import org.cashu.wallet.Models.TokenInfo
import org.cashudevkit.CurrencyUnit as CdkCurrencyUnit
import org.cashudevkit.Token as CdkToken

object TokenParser {
    private val tokenPrefixes = listOf("cashuA", "cashuB", "cashuC")

    fun extractToken(raw: String): String? {
        val trimmed = raw.trim()
        val withoutScheme = when {
            trimmed.startsWith("cashu://", ignoreCase = true) -> trimmed.drop("cashu://".length)
            trimmed.startsWith("cashu:", ignoreCase = true) -> trimmed.drop("cashu:".length)
            else -> trimmed
        }
        return withoutScheme.takeIf { tokenPrefixes.any { prefix -> it.startsWith(prefix, ignoreCase = true) } }
    }

    fun isCashuToken(raw: String): Boolean = extractToken(raw) != null

    fun tokenInfo(from: String): TokenInfo? {
        val token = extractToken(from) ?: return null
        val decoded = runCatching { CdkToken.decode(token) }.getOrNull() ?: return null
        val proofs = runCatching { decoded.proofsSimple() }.getOrDefault(emptyList())
        return TokenInfo(
            amount = runCatching { decoded.value().value.toLong() }.getOrDefault(0),
            mint = runCatching { decoded.mintUrl().url }.getOrDefault("Unknown mint"),
            unit = decoded.unit()?.toDomainUnit() ?: "sat",
            memo = decoded.memo(),
            proofCount = proofs.size,
        )
    }

    fun p2pkPubkeys(from: String): List<String> {
        val token = extractToken(from) ?: return emptyList()
        val decoded = runCatching { CdkToken.decode(token) }.getOrNull() ?: return emptyList()
        return runCatching { decoded.p2pkPubkeys() }.getOrDefault(emptyList())
    }

    private fun CdkCurrencyUnit.toDomainUnit(): String = when (this) {
        CdkCurrencyUnit.Sat -> "sat"
        CdkCurrencyUnit.Msat -> "msat"
        CdkCurrencyUnit.Usd -> "usd"
        CdkCurrencyUnit.Eur -> "eur"
        CdkCurrencyUnit.Auth -> "auth"
        is CdkCurrencyUnit.Custom -> unit
    }
}
