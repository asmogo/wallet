package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeBalanceTest {
    @Test
    fun unitsAreSatFirstThenHeldNonSatSorted() {
        val units = HomeBalance.homeBalanceUnits(
            mapOf("sat" to 100L, "usd" to 500L, "eur" to 200L, "chf" to 0L),
        )
        assertEquals(listOf("sat", "eur", "usd"), units)
    }

    @Test
    fun satIsAlwaysPresentEvenWithZeroSatBalance() {
        assertEquals(listOf("sat"), HomeBalance.homeBalanceUnits(mapOf("sat" to 0L)))
        assertEquals(listOf("sat"), HomeBalance.homeBalanceUnits(emptyMap()))
    }

    @Test
    fun resolvedUnitClampsBackToSat() {
        val units = listOf("sat", "eur")
        assertEquals("eur", HomeBalance.resolvedUnit("eur", units))
        assertEquals("sat", HomeBalance.resolvedUnit("usd", units))
    }

    @Test
    fun pagerShowsHeldCurrenciesIndependentlyOfMintAdvertisements() {
        val held = mapOf("sat" to 100L, "eur" to 200L)
        assertTrue(HomeBalance.showsUnitPager(balancesByUnit = held))
        // No held non-sat balance means there is only one page.
        assertFalse(
            HomeBalance.showsUnitPager(
                balancesByUnit = mapOf("sat" to 100L, "eur" to 0L),
            ),
        )
    }
}
