package com.cashu.me.ui.send

import com.cashu.me.Core.AmountDisplayPrimary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UnifiedSendAmountEntryTest {
    private val fiat = UnifiedSendEntryContext(
        primary = AmountDisplayPrimary.Fiat,
        btcPrice = 50_000.0,
    )
    private val sats = UnifiedSendEntryContext(
        primary = AmountDisplayPrimary.Sats,
        btcPrice = 50_000.0,
    )

    @Test
    fun savedFiatPrimaryConvertsKeypadCentsToSats() {
        assertEquals(25_000L, UnifiedSendAmountEntry.amountSats("12.50", fiat))
        assertEquals(25_000L, UnifiedSendAmountEntry.amountSats("25000", sats))
    }

    @Test
    fun fiatEntryFallsBackToSatsWithoutAUsablePrice() {
        assertEquals(
            AmountDisplayPrimary.Sats,
            UnifiedSendAmountEntry.context("fiat", btcPrice = 0.0).primary,
        )
        assertEquals(
            AmountDisplayPrimary.Sats,
            UnifiedSendAmountEntry.context("fiat", btcPrice = Double.NaN).primary,
        )
    }

    @Test
    fun validationUsesConvertedSatsAndProtectsBalanceLimit() {
        assertEquals(
            UnifiedSendAmountValidation.Empty,
            UnifiedSendAmountEntry.validation(
                amountSats = UnifiedSendAmountEntry.amountSats("", fiat),
                balanceSats = 25_000L,
            ),
        )
        assertEquals(
            UnifiedSendAmountValidation.Valid,
            UnifiedSendAmountEntry.validation(
                amountSats = UnifiedSendAmountEntry.amountSats("12.50", fiat),
                balanceSats = 25_000L,
            ),
        )
        assertEquals(
            UnifiedSendAmountValidation.InsufficientBalance,
            UnifiedSendAmountEntry.validation(
                amountSats = UnifiedSendAmountEntry.amountSats("12.51", fiat),
                balanceSats = 25_000L,
            ),
        )
        assertEquals(
            1_999_999_999_980L,
            UnifiedSendAmountEntry.amountSats("999999999999999999999999.99", fiat),
        )
        assertEquals(
            UnifiedSendAmountValidation.InsufficientBalance,
            UnifiedSendAmountEntry.validation(
                amountSats = UnifiedSendAmountEntry.amountSats(
                    "999999999999999999999999.99",
                    fiat,
                ),
                balanceSats = 25_000L,
            ),
        )
    }

    @Test
    fun sendMaxUsesFiatEntryWithoutExceedingTheSatBalance() {
        val balance = 12_350L
        val raw = UnifiedSendAmountEntry.maxRawForBalance(balance, fiat)
        val paidSats = UnifiedSendAmountEntry.amountSats(raw, fiat)

        assertEquals("6.17", raw)
        assertEquals(12_340L, paidSats)
        assertTrue(paidSats <= balance)
        assertTrue(UnifiedSendAmountEntry.amountSats("6.18", fiat) > balance)
    }

    @Test
    fun sendMaxRemainsExactInSatsPrimary() {
        assertEquals("12350", UnifiedSendAmountEntry.maxRawForBalance(12_350L, sats))
        assertEquals(
            12_350L,
            UnifiedSendAmountEntry.amountSats(
                UnifiedSendAmountEntry.maxRawForBalance(12_350L, sats),
                sats,
            ),
        )
    }
}
