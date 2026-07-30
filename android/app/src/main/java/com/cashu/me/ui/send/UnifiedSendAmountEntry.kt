package com.cashu.me.ui.send

import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.UnitAmountEntry
import kotlin.math.roundToLong

internal data class UnifiedSendEntryContext(
    val primary: AmountDisplayPrimary,
    val btcPrice: Double,
)

internal enum class UnifiedSendAmountValidation {
    Empty,
    InsufficientBalance,
    Valid,
}

/**
 * Conversion boundary for unified Send's sat-denominated payment rails.
 *
 * The keypad keeps a unit-native raw string (integer sats or fiat cents), while
 * quotes and payments always receive the converted sat value.
 */
internal object UnifiedSendAmountEntry {
    fun context(preferredPrimary: String, btcPrice: Double): UnifiedSendEntryContext {
        val preferred = AmountDisplayPrimary.fromRaw(preferredPrimary)
        val effective = if (preferred == AmountDisplayPrimary.Fiat && btcPrice.isFinite() && btcPrice > 0.0) {
            AmountDisplayPrimary.Fiat
        } else {
            AmountDisplayPrimary.Sats
        }
        return UnifiedSendEntryContext(effective, btcPrice)
    }

    fun amountSats(raw: String, context: UnifiedSendEntryContext): Long =
        when (context.primary) {
            AmountDisplayPrimary.Sats -> raw.toLongOrNull()?.takeIf { it > 0L } ?: 0L
            AmountDisplayPrimary.Fiat -> fiatCentsToSats(
                cents = UnitAmountEntry.baseUnits(raw, FIAT_DECIMALS),
                btcPrice = context.btcPrice,
            )
        }

    fun rawForSats(amountSats: Long, context: UnifiedSendEntryContext): String {
        if (amountSats <= 0L) return ""
        return when (context.primary) {
            AmountDisplayPrimary.Sats -> amountSats.toString()
            AmountDisplayPrimary.Fiat -> {
                if (!context.btcPrice.isFinite() || context.btcPrice <= 0.0) return ""
                val cents = (
                    amountSats.toDouble() /
                        SATS_PER_BITCOIN *
                        context.btcPrice *
                        CENTS_PER_FIAT
                    ).roundToLong()
                if (cents !in 1..MAX_ENTRY_BASE_UNITS) {
                    ""
                } else {
                    UnitAmountEntry.entryString(cents, FIAT_DECIMALS)
                }
            }
        }
    }

    /**
     * Fiat cents cannot represent every sat balance exactly. Pick the closest
     * keypad value that never exceeds the balance so Send Max remains valid.
     */
    fun maxRawForBalance(balanceSats: Long, context: UnifiedSendEntryContext): String {
        var raw = rawForSats(balanceSats, context)
        if (context.primary != AmountDisplayPrimary.Fiat) return raw
        var cents = UnitAmountEntry.baseUnits(raw, FIAT_DECIMALS)
        while (cents > 0L && amountSats(raw, context) > balanceSats) {
            cents -= 1L
            raw = UnitAmountEntry.entryString(cents, FIAT_DECIMALS)
        }
        return raw
    }

    fun convert(
        raw: String,
        from: UnifiedSendEntryContext,
        to: UnifiedSendEntryContext,
    ): String {
        if (raw.isEmpty() || from.primary == to.primary) return raw
        return rawForSats(amountSats(raw, from), to)
    }

    fun validation(amountSats: Long, balanceSats: Long): UnifiedSendAmountValidation =
        when {
            amountSats <= 0L -> UnifiedSendAmountValidation.Empty
            amountSats > balanceSats -> UnifiedSendAmountValidation.InsufficientBalance
            else -> UnifiedSendAmountValidation.Valid
        }

    private fun fiatCentsToSats(cents: Long, btcPrice: Double): Long {
        if (cents <= 0L || !btcPrice.isFinite() || btcPrice <= 0.0) return 0L
        val sats = cents.toDouble() /
            CENTS_PER_FIAT /
            btcPrice *
            SATS_PER_BITCOIN
        if (!sats.isFinite() || sats <= 0.0 || sats > Long.MAX_VALUE.toDouble()) return 0L
        return sats.roundToLong()
    }

    private const val FIAT_DECIMALS = 2
    private const val CENTS_PER_FIAT = 100.0
    private const val SATS_PER_BITCOIN = 100_000_000.0
    private const val MAX_ENTRY_BASE_UNITS = 99_999_999_999L
}
