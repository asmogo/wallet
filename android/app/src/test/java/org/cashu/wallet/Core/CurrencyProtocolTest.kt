package org.cashu.wallet.Core

import org.cashu.wallet.Core.Protocols.CurrencyAmount
import org.cashu.wallet.Core.Protocols.CurrencyRegistry
import org.cashu.wallet.Core.Protocols.WalletCurrencies
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
        assertNull(CurrencyRegistry.currencyForMintUnit("msat"))
    }
}
