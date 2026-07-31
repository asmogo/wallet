package com.cashu.me.ui.send

import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.UnitAmountEntry

/**
 * Amount-entry policy for Create Ecash.
 *
 * Sat-denominated ecash follows the saved sats/fiat primary unit and crosses
 * into wallet operations only after conversion back to sats. Other mint units
 * remain native base-unit entry and never pass through the BTC price.
 */
internal data class SendEcashEntryContext(
    val isSatUnit: Boolean,
    val unitDecimals: Int,
    val satEntry: UnifiedSendEntryContext,
) {
    val isFiatEntry: Boolean
        get() = isSatUnit && satEntry.primary == AmountDisplayPrimary.Fiat

    val keypadDecimals: Int
        get() = if (isFiatEntry) 2 else unitDecimals

    fun amountBaseUnits(raw: String): Long =
        if (isSatUnit) {
            UnifiedSendAmountEntry.amountSats(raw, satEntry)
        } else {
            UnitAmountEntry.baseUnits(raw, unitDecimals)
        }

    fun maxRawForBalance(balance: Long): String =
        if (isSatUnit) {
            UnifiedSendAmountEntry.maxRawForBalance(balance, satEntry)
        } else {
            UnitAmountEntry.entryString(balance, unitDecimals)
        }
}

internal object SendEcashAmountEntry {
    fun context(
        unit: String,
        unitDecimals: Int,
        preferredPrimary: String,
        btcPrice: Double,
    ): SendEcashEntryContext = SendEcashEntryContext(
        isSatUnit = unit.equals("sat", ignoreCase = true),
        unitDecimals = unitDecimals,
        satEntry = UnifiedSendAmountEntry.context(preferredPrimary, btcPrice),
    )

    /**
     * Re-express a live sat amount only when its effective entry unit changes.
     * Unit-picker changes clear the entry separately, so native mint-unit
     * amounts are deliberately never reinterpreted as sats or fiat.
     */
    fun convert(
        raw: String,
        from: SendEcashEntryContext,
        to: SendEcashEntryContext,
    ): String {
        if (!from.isSatUnit || !to.isSatUnit) return raw
        return UnifiedSendAmountEntry.convert(raw, from.satEntry, to.satEntry)
    }
}
