package com.cashu.me.ui.receive

import com.cashu.me.Core.AmountDisplayPrimary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiveAmountEntryTest {
    @Test
    fun fiatPrimaryConvertsEntryAndKeepsTheQuoteDenominatedInSats() {
        val context = satContext(preferredPrimary = "fiat", btcPrice = 50_000.0)

        assertTrue(context.isFiatPrimary)
        assertEquals(2, context.entryDecimals)
        assertEquals(ReceiveAmountValidation.Valid, ReceiveAmountEntry.validation("12.50", context))
        assertEquals(25_000L, ReceiveAmountEntry.quoteAmount("12.50", context, amountless = false))
        assertEquals("sat", context.quoteUnit)
    }

    @Test
    fun validationRejectsAnEmptyFiatEntryAfterConversion() {
        val context = satContext(preferredPrimary = "fiat", btcPrice = 50_000.0)

        assertEquals(ReceiveAmountValidation.Empty, ReceiveAmountEntry.validation("", context))
        assertEquals(null, ReceiveAmountEntry.quoteAmount("", context, amountless = false))
    }

    @Test
    fun unavailablePriceFallsBackToIntegerSatEntry() {
        val context = satContext(preferredPrimary = "fiat", btcPrice = 0.0)

        assertFalse(context.isFiatPrimary)
        assertEquals(AmountDisplayPrimary.Sats, context.bitcoin.primary)
        assertEquals(0, context.entryDecimals)
        assertEquals(12_500L, ReceiveAmountEntry.quoteAmount("12500", context, amountless = false))
    }

    @Test
    fun priceAvailabilityReexpressesExistingSatsWithoutChangingTheQuoteAmount() {
        val sats = satContext(preferredPrimary = "fiat", btcPrice = 0.0)
        val fiat = satContext(preferredPrimary = "fiat", btcPrice = 50_000.0)

        val convertedRaw = ReceiveAmountEntry.convert("25000", from = sats, to = fiat)

        assertEquals("12.50", convertedRaw)
        assertEquals(25_000L, ReceiveAmountEntry.quoteAmount(convertedRaw, fiat, amountless = false))
    }

    @Test
    fun nonSatMintUnitsRemainUnitNative() {
        val context = ReceiveAmountEntry.context(
            quoteUnit = "usd",
            mintUnitDecimals = 2,
            preferredPrimary = "fiat",
            btcPrice = 50_000.0,
        )

        assertFalse(context.isFiatPrimary)
        assertEquals(2, context.entryDecimals)
        assertEquals(1_250L, ReceiveAmountEntry.quoteAmount("12.50", context, amountless = false))
        assertEquals("usd", context.quoteUnit)
    }

    @Test
    fun amountlessQuotesIgnoreAnyTypedValue() {
        val context = satContext(preferredPrimary = "fiat", btcPrice = 50_000.0)

        assertEquals(null, ReceiveAmountEntry.quoteAmount("12.50", context, amountless = true))
    }

    private fun satContext(
        preferredPrimary: String,
        btcPrice: Double,
    ): ReceiveAmountEntryContext = ReceiveAmountEntry.context(
        quoteUnit = "sat",
        mintUnitDecimals = 0,
        preferredPrimary = preferredPrimary,
        btcPrice = btcPrice,
    )
}
