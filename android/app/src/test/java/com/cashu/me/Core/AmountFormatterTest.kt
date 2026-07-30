package com.cashu.me.Core

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AmountFormatterTest {
    private val formatter = AmountFormatter(Locale.US)

    @Test
    fun walletSatsUseSatUnitByDefault() {
        assertEquals("1,234 sat", formatter.formatWalletSats(1_234, useBitcoinSymbol = false))
    }

    @Test
    fun walletSatsUseBitcoinSymbolWithSatCount() {
        assertEquals("₿1,234", formatter.formatWalletSats(1_234, useBitcoinSymbol = true))
    }

    @Test
    fun walletSatsCanOmitUnitWhenBitcoinSymbolIsDisabled() {
        assertEquals("1,234", formatter.formatWalletSats(1_234, useBitcoinSymbol = false, includeUnit = false))
    }

    @Test
    fun amountDisplayPrimaryNormalizesStoredValues() {
        assertEquals(AmountDisplayPrimary.Sats, AmountDisplayPrimary.fromRaw(" SATS "))
        assertEquals(AmountDisplayPrimary.Fiat, AmountDisplayPrimary.fromRaw("unknown"))
        assertEquals(AmountDisplayPrimary.Fiat, AmountDisplayPrimary.fromRaw(null))
    }

    @Test
    fun fiatPrimaryFallsBackToSatsWhenPriceIsUnavailable() {
        val display = formatter.displayText(
            amountSats = 25_000,
            preferredPrimary = AmountDisplayPrimary.Fiat.rawValue,
            showFiat = true,
            btcPrice = 0.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
        )

        assertEquals("25,000 sat", display.primary)
        assertNull(display.secondary)
        assertEquals(AmountDisplayPrimary.Sats, display.effectivePrimary)
    }

    @Test
    fun fiatPrimaryShowsSatsAsSecondaryWhenPriceIsAvailable() {
        val display = formatter.displayText(
            amountSats = 100_000_000,
            preferredPrimary = AmountDisplayPrimary.Fiat.rawValue,
            showFiat = true,
            btcPrice = 20_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = true,
        )

        assertEquals("$20,000.00", display.primary)
        assertEquals("₿100,000,000", display.secondary)
        assertEquals(AmountDisplayPrimary.Fiat, display.effectivePrimary)
    }

    @Test
    fun satsPrimaryShowsFiatAsSecondaryWhenPriceIsAvailable() {
        val display = formatter.displayText(
            amountSats = 100_000_000,
            preferredPrimary = AmountDisplayPrimary.Sats.rawValue,
            showFiat = true,
            btcPrice = 20_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
        )

        assertEquals("100,000,000 sat", display.primary)
        assertEquals("$20,000.00", display.secondary)
        assertEquals(AmountDisplayPrimary.Sats, display.effectivePrimary)
    }

    @Test
    fun formatFiatShowsExactlyOneCent() {
        // 50 sats at $20k/BTC = $0.01 — the smallest displayable amount.
        assertEquals("$0.01", formatter.formatFiat(amountSats = 50, btcPrice = 20_000.0, currencyCode = "USD"))
    }

    @Test
    fun formatFiatHidesSubCentAmounts() {
        // 49 sats at $20k/BTC = $0.0098 — sub-cent conversions are never shown.
        assertNull(formatter.formatFiat(amountSats = 49, btcPrice = 20_000.0, currencyCode = "USD"))
    }

    @Test
    fun fiatEntryPreservesKeypadCentsWithTheCurrencySymbol() {
        assertEquals("$1,234.50", formatter.entryFiatDisplay(raw = "1234.50", currencyCode = "USD"))
    }

    @Test
    fun usdUsesBareLeadingDollarSymbolRegardlessOfDeviceLocale() {
        val germanFormatter = AmountFormatter(Locale.GERMANY)

        assertEquals(
            "$60.00",
            germanFormatter.formatFiat(
                amountSats = 300_000,
                btcPrice = 20_000.0,
                currencyCode = "USD",
            ),
        )
    }
}
