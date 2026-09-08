package com.cashu.me.ui.send

import com.cashu.me.Core.PaymentRequestDecodeResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SendDestinationResolverTest {
    @Test
    fun realAmountlessBolt11FixtureShowsHintInsteadOfAdvancing() {
        val resolution = resolveSendDestination(Bolt11AmountlessDonationInvoice, walletMints = emptyList())

        assertEquals(
            SendDestinationResolution.Hint(AmountlessBolt11Hint),
            resolution,
        )
    }

    @Test
    fun amountlessBolt12OfferRoutesToAmountEntry() {
        val resolution = resolveSendDestination("lightning:$AmountlessBolt12Offer", walletMints = emptyList())

        assertTrue(resolution is SendDestinationResolution.Melt)
        val melt = resolution as SendDestinationResolution.Melt
        assertEquals(AmountlessBolt12Offer, melt.request)
        assertEquals(null, melt.knownAmount)
        assertTrue(melt.requiresAmountEntry)
        assertTrue(melt.decoded is PaymentRequestDecodeResult.Bolt12)
    }

    @Test
    fun amountCarryingBolt11RoutesDirectlyToConfirm() {
        val resolution = resolveSendDestination(Bolt11AmountfulCoffeeInvoice, walletMints = emptyList())

        assertTrue(resolution is SendDestinationResolution.Melt)
        val melt = resolution as SendDestinationResolution.Melt
        assertEquals(250_000L, melt.knownAmount)
        assertFalse(melt.requiresAmountEntry)
        assertTrue(melt.decoded is PaymentRequestDecodeResult.Bolt11)
    }

    @Test
    fun lightningAddressRequiresAmountEntry() {
        val resolution = resolveSendDestination("alice@example.com", walletMints = emptyList())

        assertTrue(resolution is SendDestinationResolution.Melt)
        val melt = resolution as SendDestinationResolution.Melt
        assertEquals(null, melt.knownAmount)
        assertTrue(melt.requiresAmountEntry)
        assertTrue(melt.decoded is PaymentRequestDecodeResult.LightningAddress)
    }

    @Test
    fun ecashTokenIsRoutedToReceiveHandoff() {
        val token = "cashuA-test-token"
        val resolution = resolveSendDestination(token, walletMints = emptyList())

        assertEquals(SendDestinationResolution.EcashToken(token), resolution)
    }

    @Test
    fun malformedBolt11DoesNotAdvanceAfterStrictDecodingFails() {
        val inputs = listOf(
            "lnbc10u1bogus", "lightning:lnbc10u1bogus", "LNBC10U1BOGUS",
            Bolt11AmountfulCoffeeInvoice.dropLast(1),
            Bolt11AmountfulCoffeeInvoice.dropLast(1) + "q",
        )
        inputs.forEach { input ->
            assertEquals(SendDestinationResolution.Unrecognized,
                resolveSendDestination(input, walletMints = emptyList()))
        }
    }

    private companion object {
        private const val AmountlessBolt12Offer =
            "lno1pgqpvggr25nht4nyqrgtnhxltctkdsfrf3myhj008f6fyulf4tplmarx8hxq"

        // BOLT #11 example: donation invoice with no amount in the HRP.
        private const val Bolt11AmountlessDonationInvoice =
            "lnbc1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq9qrsgq357wnc5r2ueh7ck6q93dj32dlqnls087fxdwk8qakdyafkq3yap9us6v52vjjsrvywa6rt52cm9r9zqt8r2t7mlcwspyetp5h2tztugp9lfyql"

        // BOLT #11 example: fixed amount invoice for 2500 micro-bitcoin.
        private const val Bolt11AmountfulCoffeeInvoice =
            "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh"
    }
}
