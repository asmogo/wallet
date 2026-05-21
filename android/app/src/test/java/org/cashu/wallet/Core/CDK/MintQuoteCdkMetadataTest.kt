package org.cashu.wallet.Core.CDK

import org.cashu.wallet.Core.LOCAL_NEVER_EXPIRES_EPOCH_SECONDS
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashudevkit.Amount as CdkAmount
import org.cashudevkit.CurrencyUnit as CdkCurrencyUnit
import org.cashudevkit.MintQuote as CdkMintQuote
import org.cashudevkit.MintUrl as CdkMintUrl
import org.cashudevkit.PaymentMethod as CdkPaymentMethod
import org.cashudevkit.QuoteState as CdkQuoteState
import org.cashudevkit.SplitTarget as CdkSplitTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MintQuoteCdkMetadataTest {
    @Test
    fun bolt12ZeroExpiryIsNormalizedToLocalNeverExpiresSentinelForStorage() {
        val quote = quote(expiry = 0uL, paymentMethod = CdkPaymentMethod.Bolt12)

        val normalized = quote.withLocalMintQuoteMetadata(PaymentMethodKind.Bolt12)

        assertEquals(LOCAL_NEVER_EXPIRES_EPOCH_SECONDS.toULong(), normalized.expiry)
    }

    @Test
    fun refreshedQuotePreservesLocalMetadataWhenCdkOmitsFields() {
        val existing = quote(
            request = "existing-request",
            amount = CdkAmount(42uL),
            expiry = LOCAL_NEVER_EXPIRES_EPOCH_SECONDS.toULong(),
            paymentMethod = CdkPaymentMethod.Bolt12,
            estimatedBlocks = 6u,
            secretKey = "secret",
            usedByOperation = "operation-id",
        )
        val refreshed = quote(
            request = "",
            amount = null,
            expiry = 0uL,
            paymentMethod = CdkPaymentMethod.Custom("unknown"),
            estimatedBlocks = null,
            secretKey = null,
            usedByOperation = null,
        )

        val preserved = refreshed.preservingLocalMetadataFrom(existing)

        assertEquals("existing-request", preserved.request)
        assertEquals(42uL, preserved.amount?.value)
        assertEquals(LOCAL_NEVER_EXPIRES_EPOCH_SECONDS.toULong(), preserved.expiry)
        assertEquals(CdkPaymentMethod.Bolt12, preserved.paymentMethod)
        assertEquals(6u, preserved.estimatedBlocks)
        assertEquals("secret", preserved.secretKey)
        assertEquals("operation-id", preserved.usedByOperation)
    }

    @Test
    fun clearingReservationOnlyRemovesUsedByOperation() {
        val quote = quote(usedByOperation = "operation-id", secretKey = "secret")

        val cleared = quote.clearingReservation()

        assertNull(cleared.usedByOperation)
        assertEquals("secret", cleared.secretKey)
    }

    @Test
    fun onchainLocalMetadataStoresFallbackAmountWhenCdkOmitsAmount() {
        val quote = quote(amount = null, paymentMethod = CdkPaymentMethod.Onchain)

        val normalized = quote.withLocalMintQuoteMetadata(PaymentMethodKind.Onchain, fallbackAmount = 42)

        assertEquals(42uL, normalized.amount?.value)
    }

    @Test
    fun onchainLocalMetadataPrefersCreditedAmountBeforeFallback() {
        val quote = quote(
            amount = null,
            paymentMethod = CdkPaymentMethod.Onchain,
            amountPaid = CdkAmount(21uL),
        )

        val normalized = quote.withLocalMintQuoteMetadata(PaymentMethodKind.Onchain, fallbackAmount = 42)

        assertEquals(21uL, normalized.amount?.value)
    }

    @Test
    fun onchainMintSplitTargetUsesStoredAmount() {
        val target = quote(
            amount = CdkAmount(64uL),
            paymentMethod = CdkPaymentMethod.Onchain,
            amountPaid = CdkAmount(80uL),
        ).mintAmountSplitTarget(PaymentMethodKind.Onchain)

        assertTrue(target is CdkSplitTarget.Value)
        assertEquals(64uL, (target as CdkSplitTarget.Value).amount.value)
    }

    @Test
    fun onchainMintSplitTargetFallsBackToCreditedAmount() {
        val target = quote(
            amount = null,
            paymentMethod = CdkPaymentMethod.Onchain,
            amountPaid = CdkAmount(80uL),
        ).mintAmountSplitTarget(PaymentMethodKind.Onchain)

        assertTrue(target is CdkSplitTarget.Value)
        assertEquals(80uL, (target as CdkSplitTarget.Value).amount.value)
    }

    @Test
    fun nonOnchainMintSplitTargetIsNone() {
        val target = quote(amount = CdkAmount(64uL)).mintAmountSplitTarget(PaymentMethodKind.Bolt11)

        assertTrue(target is CdkSplitTarget.None)
    }

    @Test
    fun onchainCreditIsMintableOnlyWhenPaidExceedsIssued() {
        assertFalse(
            quote(
                paymentMethod = CdkPaymentMethod.Onchain,
                amountPaid = CdkAmount(21uL),
                amountIssued = CdkAmount(21uL),
            ).hasUnissuedOnchainCredit(),
        )
        assertTrue(
            quote(
                paymentMethod = CdkPaymentMethod.Onchain,
                amountPaid = CdkAmount(21uL),
                amountIssued = CdkAmount(0uL),
            ).hasUnissuedOnchainCredit(),
        )
    }

    private fun quote(
        request: String = "request",
        amount: CdkAmount? = CdkAmount(1uL),
        expiry: ULong = 100uL,
        paymentMethod: CdkPaymentMethod = CdkPaymentMethod.Bolt11,
        amountPaid: CdkAmount = CdkAmount(0uL),
        amountIssued: CdkAmount = CdkAmount(0uL),
        estimatedBlocks: UInt? = null,
        secretKey: String? = null,
        usedByOperation: String? = null,
    ) = CdkMintQuote(
        id = "quote-id",
        amount = amount,
        unit = CdkCurrencyUnit.Sat,
        request = request,
        state = CdkQuoteState.UNPAID,
        expiry = expiry,
        mintUrl = CdkMintUrl("https://mint.example.com"),
        amountIssued = amountIssued,
        amountPaid = amountPaid,
        estimatedBlocks = estimatedBlocks,
        paymentMethod = paymentMethod,
        secretKey = secretKey,
        usedByOperation = usedByOperation,
        version = 0u,
    )
}
