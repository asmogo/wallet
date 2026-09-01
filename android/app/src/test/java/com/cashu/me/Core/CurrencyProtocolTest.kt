package com.cashu.me.Core

import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.Protocols.WalletCurrencies
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CurrencyProtocolTest {
    @Test
    fun currencyAmountsFormatWithSwiftCompatibleSymbolsAndGrouping() {
        assertEquals("₿1,234", CurrencyAmount.sats(1_234).formatted())
        assertEquals("$12.34", CurrencyAmount.usdCents(1_234).formatted())
        assertEquals("€12.34", CurrencyAmount.eurCents(1_234).formatted())
        assertEquals("12.34", CurrencyAmount.usdCents(1_234).formatted(showSymbol = false))
    }

    @Test
    fun displayValueUsesCurrencyDecimals() {
        assertEquals(1_234.0, CurrencyAmount.sats(1_234).displayValue, 0.0)
        assertEquals(12.34, CurrencyAmount.usdCents(1_234).displayValue, 0.0)
    }

    @Test
    fun registryLooksUpCodesCaseInsensitively() {
        assertEquals(WalletCurrencies.Satoshi, CurrencyRegistry.currencyForCode("sat"))
        assertEquals(WalletCurrencies.Usd, CurrencyRegistry.currencyForCode(" USD "))
        assertEquals(WalletCurrencies.Eur, CurrencyRegistry.currencyForCode("eur"))
        assertNull(CurrencyRegistry.currencyForCode("gbp"))
    }

    @Test
    fun registryMapsMintUnitsToCurrencies() {
        assertEquals(WalletCurrencies.Satoshi, CurrencyRegistry.currencyForMintUnit("satoshis"))
        assertEquals(WalletCurrencies.Usd, CurrencyRegistry.currencyForMintUnit("dollars"))
        assertEquals(WalletCurrencies.Eur, CurrencyRegistry.currencyForMintUnit("euros"))
    }

    @Test
    fun registryFallsBackToGenericCodeAfterCurrencyForUnknownUnits() {
        val generic = CurrencyRegistry.currencyForMintUnit("chf")
        assertEquals("CHF", generic.code)
        assertEquals(0, generic.decimals)
        assertEquals("100 CHF", CurrencyAmount(100, generic).formatted())
    }

    @Test
    fun transactionAmountsUseTheirNativeMintUnit() {
        val display = AmountFormatter().displayMintUnitAmount(
            amount = 500,
            unit = "usd",
            preferredPrimary = "fiat",
            showFiat = true,
            btcPrice = 20_000.0,
            currencyCode = "EUR",
            useBitcoinSymbol = false,
        )

        assertEquals("\$5.00", display.primary)
        assertNull(display.secondary)
    }

    @Test
    fun historyAmountsConvertEverySatoshiUnitAlias() {
        listOf("sat", "SAT", " sats ", "satoshi", "satoshis").forEach { unit ->
            val display = AmountFormatter().displayMintUnitAmount(
                amount = 300_000,
                unit = unit,
                preferredPrimary = "fiat",
                showFiat = true,
                btcPrice = 20_000.0,
                currencyCode = "USD",
                useBitcoinSymbol = false,
            )

            assertEquals("Failed for unit: $unit", "\$60.00", display.primary)
            assertEquals("Failed for unit: $unit", "300,000 sat", display.secondary)
            assertEquals("Failed for unit: $unit", AmountDisplayPrimary.Fiat, display.effectivePrimary)
        }
    }
}
