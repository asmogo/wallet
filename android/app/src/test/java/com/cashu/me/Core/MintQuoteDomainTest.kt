package com.cashu.me.Core

import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MintQuoteDomainTest {
    @Test
    fun normalizesDescriptionForPayerDisplay() {
        assertEquals("Coffee tips Thank you ☕", normalizedOfferDescription("  Coffee tips\r\n\tThank you ☕  "))
        assertEquals("Coffee", normalizedOfferDescription("Cof\u0000fee"))
        assertNull(normalizedOfferDescription(" \r\n\t "))
        assertEquals("a".repeat(640), normalizedOfferDescription("a".repeat(650)))
        assertEquals("a".repeat(639), normalizedOfferDescription("a".repeat(639) + "😀"))
    }

    @Test
    fun findsReusableBolt12OfferOnlyForItsMintAndUnit() {
        val offer = MintQuoteInfo(
            id = "reusable-usd",
            request = "lno1offer",
            amount = null,
            paymentMethod = PaymentMethodKind.Bolt12,
            state = MintQuoteState.Issued,
            expiryEpochSeconds = null,
            mintUrl = "https://mint.example",
            unit = "usd",
        )

        val paidOffer = offer.copy(amount = 21)
        val selected = findExistingAmountlessBolt12Offer(
            quotes = listOf(
                offer.copy(id = "other-mint", mintUrl = "https://other.example"),
                offer.copy(id = "other-unit", unit = "sat"),
                paidOffer,
            ),
            mintUrl = "https://mint.example",
            unit = "USD",
        )

        assertEquals(paidOffer, selected)
    }

    @Test
    fun reusableBolt12OfferReuseMatchesDescriptionExactly() {
        val plain = MintQuoteInfo(
            id = "plain",
            request = "lno1plain",
            amount = null,
            paymentMethod = PaymentMethodKind.Bolt12,
            state = MintQuoteState.Pending,
            expiryEpochSeconds = null,
            mintUrl = "https://mint.example",
            unit = "sat",
        )
        val described = plain.copy(id = "described", description = "Coffee tips")
        val quotes = listOf(plain, described)

        // Nil description reuses only the plain offer.
        assertEquals(
            plain,
            findExistingAmountlessBolt12Offer(
                quotes = quotes,
                mintUrl = "https://mint.example",
                unit = "sat",
                description = null,
            ),
        )
        // A set description reuses only the offer carrying the same memo.
        assertEquals(
            described,
            findExistingAmountlessBolt12Offer(
                quotes = quotes,
                mintUrl = "https://mint.example",
                unit = "sat",
                description = "Coffee tips",
            ),
        )
        // A changed description matches nothing, so the caller mints fresh.
        assertNull(
            findExistingAmountlessBolt12Offer(
                quotes = quotes,
                mintUrl = "https://mint.example",
                unit = "sat",
                description = "Different memo",
            ),
        )
        // A plain-offer lookup ignores described offers entirely.
        assertNull(
            findExistingAmountlessBolt12Offer(
                quotes = listOf(described),
                mintUrl = "https://mint.example",
                unit = "sat",
                description = null,
            ),
        )
    }

    @Test
    fun bolt12ZeroExpiryUsesLocalNeverExpiresSentinelForStorageAndIsHiddenForDisplay() {
        val stored = mintQuoteLocalStorageExpiry(0, PaymentMethodKind.Bolt12)

        assertEquals(LOCAL_NEVER_EXPIRES_EPOCH_SECONDS, stored)
        assertNull(mintQuoteDisplayExpiry(stored))
    }

    @Test
    fun nonBolt12ZeroExpiryRemainsZeroAndIsHiddenForDisplay() {
        val stored = mintQuoteLocalStorageExpiry(0, PaymentMethodKind.Bolt11)

        assertEquals(0L, stored)
        assertNull(mintQuoteDisplayExpiry(stored))
    }

    @Test
    fun bolt12StateUsesPaidAndIssuedAmountsBeforeStoredState() {
        assertEquals(
            MintQuoteState.Paid,
            mintQuoteStateForDomain(
                paymentMethod = PaymentMethodKind.Bolt12,
                storedState = MintQuoteState.Unpaid,
                amountPaid = 21,
                amountIssued = 0,
            ),
        )
        assertEquals(
            MintQuoteState.Issued,
            mintQuoteStateForDomain(
                paymentMethod = PaymentMethodKind.Bolt12,
                storedState = MintQuoteState.Unpaid,
                amountPaid = 21,
                amountIssued = 21,
            ),
        )
    }

    @Test
    fun paidAmountIsPreferredBeforeLocalFallbackForDomainDisplay() {
        assertEquals(
            75L,
            mintQuoteAmountForDomain(
                quoteAmount = null,
                fallbackAmount = 50,
                amountPaid = 75,
                amountIssued = 0,
            ),
        )
    }

    @Test
    fun issuedAmountIsLastResortForDomainDisplay() {
        assertEquals(
            25L,
            mintQuoteAmountForDomain(
                quoteAmount = null,
                fallbackAmount = null,
                amountPaid = 0,
                amountIssued = 25,
            ),
        )
    }

    @Test
    fun reusableBolt12WithoutPaymentIsPendingRatherThanUnpaid() {
        assertEquals(
            MintQuoteState.Pending,
            mintQuoteStateForDomain(
                paymentMethod = PaymentMethodKind.Bolt12,
                storedState = MintQuoteState.Unpaid,
                amountPaid = 0,
                amountIssued = 0,
            ),
        )
    }
}
