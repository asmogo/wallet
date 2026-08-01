package com.cashu.me.Core

import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tri-state NUT-04/05 rails on [MintInfo]: null = never fetched (compatibility
 * default applies), empty = reported-absent (stays empty), non-empty = reported.
 */
class MintInfoMethodsTest {

    @Test
    fun unknownRailsFallBackToBolt11CompatibilityDefault() {
        val mint = MintInfo(url = "https://mint.example")

        assertEquals(listOf(PaymentMethodKind.Bolt11), mint.effectiveMintMethods)
        assertEquals(listOf(PaymentMethodKind.Bolt11), mint.effectiveMeltMethods)
    }

    @Test
    fun reportedEmptyRailsStayEmpty() {
        val mint = MintInfo(
            url = "https://mint.example",
            supportedMintMethods = emptyList(),
            supportedMeltMethods = emptyList(),
        )

        assertTrue(mint.effectiveMintMethods.isEmpty())
        assertTrue(mint.effectiveMeltMethods.isEmpty())
    }

    @Test
    fun reportedRailsPassThrough() {
        val mint = MintInfo(
            url = "https://mint.example",
            supportedMintMethods = listOf(PaymentMethodKind.Bolt12),
            supportedMeltMethods = listOf(PaymentMethodKind.Bolt11, PaymentMethodKind.Onchain),
        )

        assertEquals(listOf(PaymentMethodKind.Bolt12), mint.effectiveMintMethods)
        assertEquals(listOf(PaymentMethodKind.Bolt11, PaymentMethodKind.Onchain), mint.effectiveMeltMethods)
    }

    @Test
    fun meltSelectionAssumesBolt11OnlyForUnfetchedMints() {
        val unfetched = MintInfo(url = "https://unfetched.example", balance = 100)
        val reportedEmpty = MintInfo(
            url = "https://empty.example",
            balance = 100,
            supportedMeltMethods = emptyList(),
        )

        val bolt11Compatible = compatibleMintsForMeltPayment(
            mints = listOf(unfetched, reportedEmpty),
            paymentMethod = PaymentMethodKind.Bolt11,
        )
        val onchainCompatible = compatibleMintsForMeltPayment(
            mints = listOf(unfetched, reportedEmpty),
            paymentMethod = PaymentMethodKind.Onchain,
        )

        // Unknown (never fetched) keeps the BOLT11 compatibility default…
        assertEquals(listOf(unfetched), bolt11Compatible)
        // …but only for BOLT11, and a mint that reported no melt rails is excluded.
        assertTrue(onchainCompatible.isEmpty())
    }
}
