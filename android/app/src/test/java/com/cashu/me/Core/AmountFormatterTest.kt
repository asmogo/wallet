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
    fun satsPrimaryHidesFiatWhenDisplayIsDisabled() {
        val display = formatter.displayText(
            amountSats = 100_000_000,
            preferredPrimary = AmountDisplayPrimary.Sats.rawValue,
            showFiat = false,
            btcPrice = 20_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
        )

        assertEquals("100,000,000 sat", display.primary)
        assertNull(display.secondary)
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

    // ---------------------------------------------------------------------
    // AmountParts
    //
    // The typographic split. The unit must never be baked into the numeral
    // string, or the hero cannot subordinate it. These pin the split against
    // the string API it was derived from, so the two cannot drift.
    // ---------------------------------------------------------------------

    @Test
    fun satsPartsSeparateTheUnitWordFromTheNumerals() {
        val parts = formatter.satsParts(21_000, useBitcoinSymbol = false)
        assertEquals("21,000", parts.value)
        assertEquals(AmountParts.Affix.Suffix("sat"), parts.affix)
        assertEquals("21,000 sat", parts.joined)
    }

    @Test
    fun satsPartsSeparateTheSymbolFromTheNumerals() {
        val parts = formatter.satsParts(21_000, useBitcoinSymbol = true)
        assertEquals("21,000", parts.value)
        assertEquals(AmountParts.Affix.Prefix("₿"), parts.affix)
        assertEquals("₿21,000", parts.joined)
    }

    /**
     * The numerals must be identical either way. If the symbol leaked into
     * `value`, the two heroes would set different strings at different widths
     * for the same amount.
     */
    @Test
    fun satsPartsValueIsUnitAgnostic() {
        assertEquals(
            formatter.satsParts(1_234_567, useBitcoinSymbol = false).value,
            formatter.satsParts(1_234_567, useBitcoinSymbol = true).value,
        )
    }

    @Test
    fun satsPartsJoinMatchesTheStringApi() {
        for (amount in listOf(0L, 1L, 100L, 1_000L, 1_000_000L, 2_100_000_000_000_000L)) {
            for (symbol in listOf(false, true)) {
                assertEquals(
                    "split diverged from formatWalletSats($amount, useBitcoinSymbol = $symbol)",
                    formatter.formatWalletSats(amount, useBitcoinSymbol = symbol),
                    formatter.satsParts(amount, useBitcoinSymbol = symbol).joined,
                )
            }
        }
    }

    /**
     * Guards the one place the two conventions could diverge: a unit *word*
     * joins with a space, a trailing currency *symbol* joins without one. Every
     * currency the app offers is prefix-positioned under the pinned US locale,
     * so this holds today — and fails loudly if that ever changes.
     */
    @Test
    fun fiatPartsJoinMatchesFormatFiat() {
        for (code in SettingsManager.supportedFiatCurrencies) {
            val expected = formatter.formatFiat(
                amountSats = 300_000,
                btcPrice = 20_000.0,
                currencyCode = code,
            )
            val parts = formatter.fiatParts(
                amountSats = 300_000,
                btcPrice = 20_000.0,
                currencyCode = code,
            )
            assertEquals("split diverged from formatFiat for $code", expected, parts?.joined)
        }
    }

    @Test
    fun fiatPartsHideSubCentAmountsLikeFormatFiat() {
        assertNull(formatter.fiatParts(amountSats = 49, btcPrice = 20_000.0, currencyCode = "USD"))
        assertNull(formatter.fiatParts(amountSats = 1_000, btcPrice = null, currencyCode = "USD"))
    }

    @Test
    fun entryPartsSeparateTheMintUnitCode() {
        val parts = formatter.entryParts(
            raw = "12.50",
            isSat = false,
            unit = "usd",
            useBitcoinSymbol = false,
        )
        assertEquals("12.50", parts.value)
        assertEquals(AmountParts.Affix.Suffix("USD"), parts.affix)
    }

    @Test
    fun entryFiatPartsSeparateTheCurrencySymbol() {
        val parts = formatter.entryFiatParts(raw = "1234.50", currencyCode = "USD")
        assertEquals("1,234.50", parts.value)
        assertEquals(AmountParts.Affix.Prefix("$"), parts.affix)
    }

    /** TalkBack reads the word, never the glyph. */
    @Test
    fun spokenFormExpandsTheBitcoinSymbol() {
        assertEquals("500 sats", formatter.satsParts(500, useBitcoinSymbol = true).spoken)
        assertEquals("500 sat", formatter.satsParts(500, useBitcoinSymbol = false).spoken)
    }
}
