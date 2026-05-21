package org.cashu.wallet.Core

import org.cashu.wallet.Models.MintQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MintQuoteDomainTest {
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
