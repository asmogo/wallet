package com.cashu.me.ui.send

import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountFormatter
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SendEcashAmountEntryTest {
    @Test
    fun savedFiatPrimaryDrivesSatEcashEntryAndValidation() {
        val context = SendEcashAmountEntry.context(
            unit = "sat",
            unitDecimals = 0,
            preferredPrimary = AmountDisplayPrimary.Fiat.rawValue,
            btcPrice = 50_000.0,
        )

        assertTrue(context.isFiatEntry)
        assertEquals(2, context.keypadDecimals)
        assertEquals(25_000L, context.amountBaseUnits("12.50"))
        assertEquals(
            UnifiedSendAmountValidation.Valid,
            UnifiedSendAmountEntry.validation(context.amountBaseUnits("12.50"), 25_000L),
        )
        assertEquals(
            UnifiedSendAmountValidation.InsufficientBalance,
            UnifiedSendAmountEntry.validation(context.amountBaseUnits("12.51"), 25_000L),
        )
    }

    @Test
    fun fiatSendMaxNeverExceedsTheAvailableSats() {
        val context = SendEcashAmountEntry.context(
            unit = "sat",
            unitDecimals = 0,
            preferredPrimary = AmountDisplayPrimary.Fiat.rawValue,
            btcPrice = 50_000.0,
        )

        val raw = context.maxRawForBalance(12_350L)

        assertEquals("6.17", raw)
        assertEquals(12_340L, context.amountBaseUnits(raw))
        assertTrue(context.amountBaseUnits(raw) <= 12_350L)
    }

    @Test
    fun savedSatsPrimaryKeepsExactSatEntryAndSendMax() {
        val context = SendEcashAmountEntry.context(
            unit = "sat",
            unitDecimals = 0,
            preferredPrimary = AmountDisplayPrimary.Sats.rawValue,
            btcPrice = 50_000.0,
        )

        assertFalse(context.isFiatEntry)
        assertEquals(0, context.keypadDecimals)
        assertEquals(12_350L, context.amountBaseUnits("12350"))
        assertEquals("12350", context.maxRawForBalance(12_350L))
    }

    @Test
    fun changingTheSavedPrimaryReexpressesTheEntryWithoutChangingSats() {
        val sats = SendEcashAmountEntry.context(
            unit = "sat",
            unitDecimals = 0,
            preferredPrimary = AmountDisplayPrimary.Sats.rawValue,
            btcPrice = 50_000.0,
        )
        val fiat = SendEcashAmountEntry.context(
            unit = "sat",
            unitDecimals = 0,
            preferredPrimary = AmountDisplayPrimary.Fiat.rawValue,
            btcPrice = 50_000.0,
        )

        val converted = SendEcashAmountEntry.convert("25000", sats, fiat)

        assertEquals("12.50", converted)
        assertEquals(25_000L, fiat.amountBaseUnits(converted))
    }

    @Test
    fun nonSatMintUnitRemainsNativeInsteadOfUsingTheBitcoinPrice() {
        val context = SendEcashAmountEntry.context(
            unit = "usd",
            unitDecimals = 2,
            preferredPrimary = AmountDisplayPrimary.Fiat.rawValue,
            btcPrice = 50_000.0,
        )

        assertFalse(context.isFiatEntry)
        assertEquals(1_250L, context.amountBaseUnits("12.50"))
        assertEquals("12.50", context.maxRawForBalance(1_250L))
    }

    @Test
    fun generatedEcashLeadsWithFiatButKeepsTheConvertedSatAmount() {
        val entry = SendEcashAmountEntry.context(
            unit = "sat",
            unitDecimals = 0,
            preferredPrimary = AmountDisplayPrimary.Fiat.rawValue,
            btcPrice = 50_000.0,
        )
        val amountSats = entry.amountBaseUnits("12.50")

        val presentation = paymentConfirmationAmountPresentation(
            amount = amountSats,
            unit = "sat",
            preferredPrimary = AmountDisplayPrimary.Fiat.rawValue,
            showFiat = true,
            btcPrice = 50_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
            formatter = AmountFormatter(Locale.US),
        )

        assertEquals(25_000L, amountSats)
        assertEquals("$12.50", presentation.primary)
        assertEquals("25,000 sat", presentation.alternate)
    }
}
