package com.cashu.me.Core

import com.cashu.me.Models.MeltPaymentResult
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.PaymentMethodKind

internal const val CASHU_REQUEST_MAX_INPUT_PROOFS = 32L

internal sealed interface CashuRequestAcquireResult {
    data class Paid(val fundingResult: MeltPaymentResult?) : CashuRequestAcquireResult

    data class NeedsExternalTopUp(
        val quote: MintQuoteInfo,
        val targetMintUrl: String,
        val requestedAmountSats: Long,
    ) : CashuRequestAcquireResult
}

internal class CashuRequestMintSettling : Exception(
    "The mint is still settling this payment. Try again in a moment.",
)

internal fun cashuRequestTopUpAmount(
    requestedAmountSats: Long,
    inputFeePpk: Long?,
    maximumInputProofs: Long = CASHU_REQUEST_MAX_INPUT_PROOFS,
): Long {
    require(requestedAmountSats > 0) { "Cashu Request top-up amount must be positive." }
    require(maximumInputProofs > 0) { "Cashu Request input-proof limit must be positive." }
    val ppk = inputFeePpk?.coerceAtLeast(0L) ?: 0L
    if (ppk == 0L) return requestedAmountSats
    val totalPpk = Math.multiplyExact(ppk, maximumInputProofs)
    val feeBuffer = Math.addExact(totalPpk, 999L) / 1_000L
    return Math.addExact(requestedAmountSats, feeBuffer.coerceAtLeast(1L))
}

internal fun selectCashuRequestFundingSource(
    mints: List<MintInfo>,
    targetMintUrl: String,
    requiredAmountSats: Long,
): MintInfo? {
    val normalizedTarget = normalizedMintUrlForSelection(targetMintUrl)
    return mints
        .asSequence()
        .filter { normalizedMintUrlForSelection(it.url) != normalizedTarget }
        .filter { PaymentMethodKind.Bolt11 in it.effectiveMeltMethods }
        .filter { it.balance >= requiredAmountSats }
        .sortedWith(compareByDescending<MintInfo> { it.balance }.thenBy { it.name.lowercase() })
        .firstOrNull()
}

internal suspend fun payCashuPaymentRequestAndRefresh(
    encoded: String,
    customAmountSats: Long?,
    preferredMintURL: String?,
    payCashuPaymentRequest: suspend (encoded: String, customAmountSats: Long?, preferredMintURL: String?) -> Unit,
    refreshBalance: suspend () -> Unit,
    loadTransactions: suspend () -> Unit,
) {
    payCashuPaymentRequest(encoded, customAmountSats, preferredMintURL)
    refreshBalance()
    loadTransactions()
}
