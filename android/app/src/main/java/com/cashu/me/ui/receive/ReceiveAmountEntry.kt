package com.cashu.me.ui.receive

import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.BitcoinAmountEntry
import com.cashu.me.Core.BitcoinAmountEntryContext
import com.cashu.me.Core.UnitAmountEntry

internal data class ReceiveAmountEntryContext(
    val quoteUnit: String,
    val mintUnitDecimals: Int,
    val bitcoin: BitcoinAmountEntryContext,
) {
    val isSatQuote: Boolean = quoteUnit.equals("sat", ignoreCase = true)
    val isFiatPrimary: Boolean = isSatQuote && bitcoin.primary == AmountDisplayPrimary.Fiat
    val entryDecimals: Int = if (isFiatPrimary) FIAT_DECIMALS else mintUnitDecimals

    private companion object {
        const val FIAT_DECIMALS = 2
    }
}

internal enum class ReceiveAmountValidation {
    Empty,
    Valid,
}

/** Amount-entry policy for receive quotes, including unit-preserving validation. */
internal object ReceiveAmountEntry {
    fun context(
        quoteUnit: String,
        mintUnitDecimals: Int,
        preferredPrimary: String,
        btcPrice: Double,
    ): ReceiveAmountEntryContext = ReceiveAmountEntryContext(
        quoteUnit = quoteUnit,
        mintUnitDecimals = mintUnitDecimals,
        bitcoin = BitcoinAmountEntry.context(preferredPrimary, btcPrice),
    )

    fun amountBaseUnits(raw: String, context: ReceiveAmountEntryContext): Long =
        if (context.isSatQuote) {
            BitcoinAmountEntry.amountSats(raw, context.bitcoin)
        } else {
            UnitAmountEntry.baseUnits(raw, context.mintUnitDecimals)
        }

    fun validation(raw: String, context: ReceiveAmountEntryContext): ReceiveAmountValidation =
        if (amountBaseUnits(raw, context) > 0L) {
            ReceiveAmountValidation.Valid
        } else {
            ReceiveAmountValidation.Empty
        }

    fun quoteAmount(
        raw: String,
        context: ReceiveAmountEntryContext,
        amountless: Boolean,
    ): Long? = if (amountless) {
        null
    } else {
        amountBaseUnits(raw, context).takeIf { it > 0L }
    }

    fun rawForBaseUnits(amount: Long, context: ReceiveAmountEntryContext): String =
        if (context.isSatQuote) {
            BitcoinAmountEntry.rawForSats(amount, context.bitcoin)
        } else {
            UnitAmountEntry.entryString(amount, context.mintUnitDecimals)
        }

    fun convert(
        raw: String,
        from: ReceiveAmountEntryContext,
        to: ReceiveAmountEntryContext,
    ): String {
        if (raw.isEmpty()) return raw
        if (!from.quoteUnit.equals(to.quoteUnit, ignoreCase = true)) return ""
        return if (from.isSatQuote && to.isSatQuote) {
            BitcoinAmountEntry.convert(raw, from.bitcoin, to.bitcoin)
        } else {
            raw
        }
    }
}
