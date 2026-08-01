package com.cashu.me.ui.send

import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.BitcoinAmountEntry
import com.cashu.me.Core.BitcoinAmountEntryContext
import com.cashu.me.Core.UnitAmountEntry

internal typealias UnifiedSendEntryContext = BitcoinAmountEntryContext

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
    fun context(preferredPrimary: String, btcPrice: Double): UnifiedSendEntryContext =
        BitcoinAmountEntry.context(preferredPrimary, btcPrice)

    fun amountSats(raw: String, context: UnifiedSendEntryContext): Long =
        BitcoinAmountEntry.amountSats(raw, context)

    fun rawForSats(amountSats: Long, context: UnifiedSendEntryContext): String =
        BitcoinAmountEntry.rawForSats(amountSats, context)

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
    ): String = BitcoinAmountEntry.convert(raw, from, to)

    fun validation(amountSats: Long, balanceSats: Long): UnifiedSendAmountValidation =
        when {
            amountSats <= 0L -> UnifiedSendAmountValidation.Empty
            amountSats > balanceSats -> UnifiedSendAmountValidation.InsufficientBalance
            else -> UnifiedSendAmountValidation.Valid
        }

    private const val FIAT_DECIMALS = 2
}
