package com.cashu.me.ui.send

import com.cashu.me.Core.CashuPaymentRequestRoute
import com.cashu.me.Core.CashuPaymentRequestSummary
import com.cashu.me.Core.PaymentRequestDecodeResult
import com.cashu.me.Core.Wallet.WalletMessage
import com.cashu.me.Models.MeltPaymentResult
import com.cashu.me.Models.MeltQuoteInfo
import com.cashu.me.Models.MeltQuoteState
import com.cashu.me.Models.MeltSettlement
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SendPaymentDetailsTest {
    @Test
    fun everyMeltRailKeepsItsDocumentedRowsThroughProcessingSuccessAndFailure() {
        val rails = listOf(
            MeltCase(
                rail = LockedRail.Melt(
                    raw = "lnbc1invoice",
                    decoded = PaymentRequestDecodeResult.Bolt11(21, "Coffee"),
                    knownAmount = 21,
                ),
                method = PaymentMethodKind.Bolt11,
                expectedKeys = StandardMeltKeys,
                expectedMethod = "BOLT11",
            ),
            MeltCase(
                rail = LockedRail.Melt(
                    raw = "lno1offer",
                    decoded = PaymentRequestDecodeResult.Bolt12(21, "Coffee"),
                    knownAmount = 21,
                ),
                method = PaymentMethodKind.Bolt12,
                expectedKeys = StandardMeltKeys,
                expectedMethod = "BOLT12",
            ),
            MeltCase(
                rail = LockedRail.Melt(
                    raw = "alice@example.com",
                    decoded = PaymentRequestDecodeResult.LightningAddress("alice@example.com"),
                    knownAmount = null,
                ),
                method = PaymentMethodKind.Bolt11,
                expectedKeys = StandardMeltKeys,
                expectedMethod = "BOLT11",
            ),
            MeltCase(
                rail = LockedRail.Melt(
                    raw = "bitcoin:bc1qrecipient?amount=0.00000021",
                    decoded = PaymentRequestDecodeResult.Onchain("bc1qrecipient"),
                    knownAmount = null,
                ),
                method = PaymentMethodKind.Onchain,
                expectedKeys = listOf(
                    SendPaymentDetailKey.Method,
                    SendPaymentDetailKey.Destination,
                    SendPaymentDetailKey.Amount,
                    SendPaymentDetailKey.NetworkFee,
                    SendPaymentDetailKey.Mint,
                ),
                expectedMethod = "On-chain",
            ),
        )

        rails.forEachIndexed { index, case ->
            val quote = meltQuote(method = case.method, id = "quote-$index")
            val details = buildSendPaymentDetails(
                rail = case.rail,
                cashuRoute = null,
                amountSats = 21,
                mint = Mint,
                meltQuote = quote,
            )
            val result = meltResult(method = case.method)

            assertStableTerminalKeys(
                processing = SendStatus.Sending(details),
                success = SendStatus.Sent(details.withMeltResult(result), result),
                failure = SendStatus.Failed(details.resolvingFailed(), WalletMessage("Mint unavailable.")),
                expected = case.expectedKeys,
            )
            assertEquals(
                SendPaymentDetailValue.Text(case.expectedMethod),
                details.value(SendPaymentDetailKey.Method),
            )
            assertEquals(SendPaymentDetailValue.Sats(21), details.value(SendPaymentDetailKey.Amount))
            assertEquals(
                SendPaymentDetailValue.Sats(3, isUpperBound = true),
                details.value(SendPaymentDetailKey.NetworkFee),
            )
            assertEquals(
                SendPaymentDetailValue.Text("Minibits"),
                details.value(SendPaymentDetailKey.Mint),
            )
        }

        val onchain = buildSendPaymentDetails(
            rail = rails.last().rail,
            cashuRoute = null,
            amountSats = 21,
            mint = Mint,
            meltQuote = meltQuote(PaymentMethodKind.Onchain),
        )
        assertEquals(
            SendPaymentDetailValue.Text("bc1qrecipient"),
            onchain.value(SendPaymentDetailKey.Destination),
        )
    }

    @Test
    fun cashuRequestKeepsAmountMethodMintInputFeeAndMemoThroughErrors() {
        val rail = cashuRail(memo = "Dinner")
        val route = CashuPaymentRequestRoute.PayWithEcash(Mint, amountSats = 21)
        val details = buildSendPaymentDetails(
            rail = rail,
            cashuRoute = route,
            amountSats = 21,
            mint = Mint,
            meltQuote = null,
            cashuInputFeeSats = 2,
        )
        val expected = listOf(
            SendPaymentDetailKey.Method,
            SendPaymentDetailKey.Amount,
            SendPaymentDetailKey.InputFee,
            SendPaymentDetailKey.Mint,
            SendPaymentDetailKey.Memo,
        )

        assertStableTerminalKeys(
            processing = SendStatus.Sending(details),
            success = SendStatus.Sent(details, null),
            failure = SendStatus.Failed(details.resolvingFailed(), WalletMessage("Request rejected.")),
            expected = expected,
        )
        assertEquals(
            SendPaymentDetailValue.Text("Cashu Request"),
            details.value(SendPaymentDetailKey.Method),
        )
        assertEquals(SendPaymentDetailValue.Sats(2), details.value(SendPaymentDetailKey.InputFee))
        assertEquals(SendPaymentDetailValue.Text("Dinner"), details.value(SendPaymentDetailKey.Memo))
    }

    @Test
    fun unknownCashuInputFeeIsUnavailableInsteadOfZero() {
        val details = buildSendPaymentDetails(
            rail = cashuRail(),
            cashuRoute = CashuPaymentRequestRoute.PayWithEcash(Mint, amountSats = 21),
            amountSats = 21,
            mint = Mint,
            meltQuote = null,
        )

        assertEquals(
            SendPaymentDetailValue.Unavailable,
            details.value(SendPaymentDetailKey.InputFee),
        )
        assertTrue(details.rows.none { it.value == SendPaymentDetailValue.Sats(0) })
    }

    @Test
    fun cashuLightningFallbackReservesFeeAndRouteRowsAcrossQuoteFailureAndSuccess() {
        val initial = buildSendPaymentDetails(
            rail = cashuRail(memo = "Dinner"),
            cashuRoute = CashuPaymentRequestRoute.PayBolt11Fallback("lnbc1fallback"),
            amountSats = 21,
            mint = Mint,
            meltQuote = null,
        )
        val quoted = initial
            .withNetworkFeeUpperBound(4)
            .withMintName("Minibits")
        val result = meltResult(PaymentMethodKind.Bolt11, feePaid = 2)
        val settled = quoted.withMeltResult(result)
        val expected = listOf(
            SendPaymentDetailKey.Method,
            SendPaymentDetailKey.Amount,
            SendPaymentDetailKey.NetworkFee,
            SendPaymentDetailKey.Mint,
            SendPaymentDetailKey.Memo,
            SendPaymentDetailKey.Route,
        )

        assertStableTerminalKeys(
            processing = SendStatus.Sending(initial),
            success = SendStatus.Sent(settled, result),
            failure = SendStatus.Failed(initial.resolvingFailed(), WalletMessage("Quote failed.")),
            expected = expected,
        )
        assertEquals(SendPaymentDetailValue.Pending, initial.value(SendPaymentDetailKey.NetworkFee))
        assertEquals(SendPaymentDetailValue.Pending, initial.value(SendPaymentDetailKey.Mint))
        assertEquals(
            SendPaymentDetailValue.Unavailable,
            initial.resolvingFailed().value(SendPaymentDetailKey.NetworkFee),
        )
        assertEquals(
            SendPaymentDetailValue.Unavailable,
            initial.resolvingFailed().value(SendPaymentDetailKey.Mint),
        )
        assertEquals(SendPaymentDetailValue.Sats(2), settled.value(SendPaymentDetailKey.NetworkFee))
        assertEquals(SendPaymentDetailValue.Text("Minibits"), settled.value(SendPaymentDetailKey.Mint))
        assertEquals(
            SendPaymentDetailValue.Text("Lightning fallback"),
            initial.value(SendPaymentDetailKey.Route),
        )
    }

    @Test
    fun cashuTopUpRouteUsesRequestedMintIdentityWithoutClaimingAnUnknownName() {
        val details = buildSendPaymentDetails(
            rail = cashuRail(),
            cashuRoute = CashuPaymentRequestRoute.AcquireThenPay(
                mintUrls = listOf("https://requested.example/path"),
                targetMintUrl = "https://requested.example/path",
                amountSats = 21,
                addsNewMint = true,
            ),
            amountSats = 21,
            mint = Mint,
            meltQuote = null,
        )

        assertEquals(
            SendPaymentDetailValue.Text("requested.example"),
            details.value(SendPaymentDetailKey.Mint),
        )
        assertEquals(
            SendPaymentDetailValue.Text("Add requested mint"),
            details.value(SendPaymentDetailKey.Route),
        )
        assertEquals(
            SendPaymentDetailValue.Pending,
            details.value(SendPaymentDetailKey.NetworkFee),
        )
    }

    @Test
    fun pendingOnchainSettlementKeepsTheFeeMarkedAsAnUpperBound() {
        val details = buildSendPaymentDetails(
            rail = LockedRail.Melt(
                raw = "bc1qrecipient",
                decoded = PaymentRequestDecodeResult.Onchain("bc1qrecipient"),
                knownAmount = null,
            ),
            cashuRoute = null,
            amountSats = 21,
            mint = Mint,
            meltQuote = meltQuote(PaymentMethodKind.Onchain),
        )
        val pending = details.withMeltResult(
            meltResult(
                method = PaymentMethodKind.Onchain,
                feePaid = 3,
                settlement = MeltSettlement.Pending,
            ),
        )

        assertEquals(
            SendPaymentDetailValue.Sats(3, isUpperBound = true),
            pending.value(SendPaymentDetailKey.NetworkFee),
        )
    }

    @Test
    fun meltUsesTheQuotedMintInsteadOfMislabelingARejectedPreference() {
        val details = buildSendPaymentDetails(
            rail = LockedRail.Melt(
                raw = "lnbc1invoice",
                decoded = PaymentRequestDecodeResult.Bolt11(21, null),
                knownAmount = 21,
            ),
            cashuRoute = null,
            amountSats = 21,
            mint = Mint,
            meltQuote = meltQuote(
                method = PaymentMethodKind.Bolt11,
                mintUrl = "https://selected.example/path",
            ),
        )

        assertEquals(
            SendPaymentDetailValue.Text("selected.example"),
            details.value(SendPaymentDetailKey.Mint),
        )
    }

    private fun assertStableTerminalKeys(
        processing: SendStatus,
        success: SendStatus,
        failure: SendStatus,
        expected: List<SendPaymentDetailKey>,
    ) {
        assertEquals(expected, processing.details.keys)
        assertEquals(expected, success.details.keys)
        assertEquals(expected, failure.details.keys)
        assertEquals(
            processing.details.rows.map { it.label },
            success.details.rows.map { it.label },
        )
        assertEquals(
            processing.details.rows.map { it.label },
            failure.details.rows.map { it.label },
        )
    }

    private fun SendPaymentDetails.value(key: SendPaymentDetailKey): SendPaymentDetailValue? =
        rows.firstOrNull { it.key == key }?.value

    private fun cashuRail(memo: String? = null) = LockedRail.Creq(
        raw = "creqArequest",
        decoded = PaymentRequestDecodeResult.CashuPaymentRequest(
            CashuPaymentRequestSummary(
                encoded = "creqArequest",
                amount = 21,
                unit = "sat",
                description = memo,
                mints = listOf(Mint.url),
            ),
        ),
        knownAmount = 21,
    )

    private fun meltQuote(
        method: PaymentMethodKind,
        id: String = "quote",
        mintUrl: String = Mint.url,
    ) = MeltQuoteInfo(
        id = id,
        mintUrl = mintUrl,
        amount = 21,
        feeReserve = 3,
        paymentMethod = method,
        state = MeltQuoteState.Unpaid,
        expiryEpochSeconds = null,
    )

    private fun meltResult(
        method: PaymentMethodKind,
        feePaid: Long = 1,
        settlement: MeltSettlement = MeltSettlement.Settled,
    ) = MeltPaymentResult(
        preimage = "preimage",
        amount = 21,
        feePaid = feePaid,
        mintUrl = Mint.url,
        paymentMethod = method,
        settlement = settlement,
    )

    private data class MeltCase(
        val rail: LockedRail.Melt,
        val method: PaymentMethodKind,
        val expectedKeys: List<SendPaymentDetailKey>,
        val expectedMethod: String,
    )

    private companion object {
        val Mint = MintInfo(
            url = "https://mint.example",
            name = "Minibits",
            balance = 100,
        )
        val StandardMeltKeys = listOf(
            SendPaymentDetailKey.Method,
            SendPaymentDetailKey.Amount,
            SendPaymentDetailKey.NetworkFee,
            SendPaymentDetailKey.Mint,
        )
    }
}
