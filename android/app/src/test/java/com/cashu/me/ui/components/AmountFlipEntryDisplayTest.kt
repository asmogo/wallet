package com.cashu.me.ui.components

import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountFormatter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class AmountFlipEntryDisplayTest {
    private val formatter = AmountFormatter(Locale.US)

    @Test
    fun fiatPrimaryKeepsMintUnitSatsVisibleAsSecondary() {
        val display = formatter.entryDisplayText(
            entryRaw = "12.50",
            amountSats = 25_000L,
            preferredPrimary = AmountDisplayPrimary.Fiat,
            btcPrice = 50_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
        )

        assertEquals(AmountDisplayPrimary.Fiat, display.effectivePrimary)
        assertEquals("$12.50", display.primary)
        assertEquals("25,000 sat", display.secondary)
    }

    @Test
    fun satsPrimaryKeepsFiatVisibleAsSecondary() {
        val display = formatter.entryDisplayText(
            entryRaw = "25000",
            amountSats = 25_000L,
            preferredPrimary = AmountDisplayPrimary.Sats,
            btcPrice = 50_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
        )

        assertEquals(AmountDisplayPrimary.Sats, display.effectivePrimary)
        assertEquals("25,000 sat", display.primary)
        assertNotNull(display.secondary)
        assertTrue(display.secondary!!.contains("12.50") || display.secondary!!.contains("$"))
    }

    @Test
    fun emptyFiatEntryStillExposesMintUnitAlternate() {
        val display = formatter.entryDisplayText(
            entryRaw = "",
            amountSats = 0L,
            preferredPrimary = AmountDisplayPrimary.Fiat,
            btcPrice = 50_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
        )

        assertEquals(AmountDisplayPrimary.Fiat, display.effectivePrimary)
        // Whole-number-first: an untouched pad has no fraction to show yet.
        assertEquals("$0", display.primary)
        assertEquals("0 sat", display.secondary)
    }

    @Test
    fun unavailablePriceFallsBackToMintUnitOnly() {
        val display = formatter.entryDisplayText(
            entryRaw = "12500",
            amountSats = 12_500L,
            preferredPrimary = AmountDisplayPrimary.Fiat,
            btcPrice = 0.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
        )

        assertEquals(AmountDisplayPrimary.Sats, display.effectivePrimary)
        assertEquals("12,500 sat", display.primary)
        assertEquals(null, display.secondary)
    }
}
