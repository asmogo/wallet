package com.cashu.me.Core

import kotlin.math.roundToLong

internal data class BitcoinAmountEntryContext(
    val primary: AmountDisplayPrimary,
    val btcPrice: Double,
)

/**
 * Shared conversion boundary for sat-denominated amount-entry surfaces.
 *
 * The keypad keeps a unit-native raw string (integer sats or fiat cents), while
 * quote and payment APIs always receive the represented sat value.
 */
internal object BitcoinAmountEntry {
    fun context(preferredPrimary: String, btcPrice: Double): BitcoinAmountEntryContext {
        val preferred = AmountDisplayPrimary.fromRaw(preferredPrimary)
        val effective = if (
            preferred == AmountDisplayPrimary.Fiat &&
            btcPrice.isFinite() &&
            btcPrice > 0.0
        ) {
            AmountDisplayPrimary.Fiat
        } else {
            AmountDisplayPrimary.Sats
        }
        return BitcoinAmountEntryContext(effective, btcPrice)
    }

    fun amountSats(raw: String, context: BitcoinAmountEntryContext): Long =
        when (context.primary) {
            AmountDisplayPrimary.Sats -> UnitAmountEntry.baseUnits(raw, 0)
            AmountDisplayPrimary.Fiat -> fiatCentsToSats(
                cents = UnitAmountEntry.baseUnits(raw, FIAT_DECIMALS),
                btcPrice = context.btcPrice,
            )
        }

    fun rawForSats(amountSats: Long, context: BitcoinAmountEntryContext): String {
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
                if (cents !in 1..UnitAmountEntry.maxBaseUnits(FIAT_DECIMALS)) {
                    ""
                } else {
                    UnitAmountEntry.entryString(cents, FIAT_DECIMALS)
                }
            }
        }
    }

    fun convert(
        raw: String,
        from: BitcoinAmountEntryContext,
        to: BitcoinAmountEntryContext,
    ): String {
        if (raw.isEmpty() || from.primary == to.primary) return raw
        return rawForSats(amountSats(raw, from), to)
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
}
