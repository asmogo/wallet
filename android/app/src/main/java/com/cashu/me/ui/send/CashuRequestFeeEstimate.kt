package com.cashu.me.ui.send

import kotlinx.coroutines.CancellationException

internal data class CashuRequestFeeEstimateKey(
    val request: String,
    val amountSats: Long,
    val mintUrl: String,
)

internal sealed interface CashuRequestFeeEstimate {
    val key: CashuRequestFeeEstimateKey?

    data object Unrequested : CashuRequestFeeEstimate {
        override val key: CashuRequestFeeEstimateKey? = null
    }

    data class Loading(
        override val key: CashuRequestFeeEstimateKey,
    ) : CashuRequestFeeEstimate

    data class NoFee(
        override val key: CashuRequestFeeEstimateKey,
    ) : CashuRequestFeeEstimate

    data class Amount(
        override val key: CashuRequestFeeEstimateKey,
        val sats: Long,
    ) : CashuRequestFeeEstimate

    data class Unavailable(
        override val key: CashuRequestFeeEstimateKey,
    ) : CashuRequestFeeEstimate
}

internal data class CashuRequestFeePresentation(
    val value: String,
    val loading: Boolean = false,
    val valueMonospaced: Boolean = false,
)

internal fun CashuRequestFeeEstimate.presentation(
    formatAmount: (Long) -> String,
): CashuRequestFeePresentation =
    when (this) {
        is CashuRequestFeeEstimate.Loading -> CashuRequestFeePresentation(
            value = "",
            loading = true,
            valueMonospaced = true,
        )
        is CashuRequestFeeEstimate.NoFee -> CashuRequestFeePresentation(value = "No fee")
        is CashuRequestFeeEstimate.Amount -> CashuRequestFeePresentation(
            value = formatAmount(sats),
            valueMonospaced = true,
        )
        CashuRequestFeeEstimate.Unrequested,
        is CashuRequestFeeEstimate.Unavailable -> CashuRequestFeePresentation(value = "Unavailable")
    }

/**
 * Compact amount-entry presentation. Before an amount exists the row reserves
 * its slot with a dash; an acquire-and-pay route reports the honest network-fee
 * category because its Lightning reserve is not known until the quote exists.
 */
internal fun CashuRequestFeeEstimate.amountEntryPresentation(
    usesNetworkRoute: Boolean,
    formatAmount: (Long) -> String,
): CashuRequestFeePresentation =
    when {
        usesNetworkRoute -> CashuRequestFeePresentation(value = "Network fee")
        this is CashuRequestFeeEstimate.Unrequested -> CashuRequestFeePresentation(value = "—")
        else -> presentation(formatAmount)
    }

internal suspend fun resolveCashuRequestFeeEstimate(
    key: CashuRequestFeeEstimateKey,
    estimate: suspend (amountSats: Long, mintUrl: String) -> Long,
): CashuRequestFeeEstimate =
    try {
        val fee = estimate(key.amountSats, key.mintUrl)
        require(fee >= 0L) { "Cashu Request fee estimate cannot be negative." }
        if (fee == 0L) {
            CashuRequestFeeEstimate.NoFee(key)
        } else {
            CashuRequestFeeEstimate.Amount(key, fee)
        }
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (_: Throwable) {
        CashuRequestFeeEstimate.Unavailable(key)
    }

/**
 * Accept a preview only while its request, amount, and mint are still current.
 * This is an explicit backstop in addition to `LaunchedEffect` cancellation.
 */
internal fun CashuRequestFeeEstimate.acceptIfCurrent(
    result: CashuRequestFeeEstimate,
): CashuRequestFeeEstimate =
    if (this is CashuRequestFeeEstimate.Loading && key == result.key) result else this
