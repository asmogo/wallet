package com.cashu.me.ui.mints

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The fiat caption beneath the mint detail's sat balance mirrors the global
 * fiat-balance preference and needs a usable BTC price; sub-cent conversions
 * stay hidden (iOS `showFiat`).
 */
class MintSatBalanceFiatSecondaryTest {

    @Test
    fun preferenceOffHidesTheCaption() {
        assertNull(
            mintSatBalanceFiatSecondary(
                balanceSats = 100_000,
                showFiat = false,
                btcPrice = 50_000.0,
                currencyCode = "USD",
            ),
        )
    }

    @Test
    fun missingPriceHidesTheCaption() {
        assertNull(
            mintSatBalanceFiatSecondary(
                balanceSats = 100_000,
                showFiat = true,
                btcPrice = 0.0,
                currencyCode = "USD",
            ),
        )
    }

    @Test
    fun subCentConversionHidesTheCaption() {
        assertNull(
            mintSatBalanceFiatSecondary(
                balanceSats = 1,
                showFiat = true,
                btcPrice = 50_000.0,
                currencyCode = "USD",
            ),
        )
    }

    @Test
    fun enabledWithPriceShowsTheConversion() {
        assertEquals(
            "$50.00",
            mintSatBalanceFiatSecondary(
                balanceSats = 100_000,
                showFiat = true,
                btcPrice = 50_000.0,
                currencyCode = "USD",
            ),
        )
    }
}
