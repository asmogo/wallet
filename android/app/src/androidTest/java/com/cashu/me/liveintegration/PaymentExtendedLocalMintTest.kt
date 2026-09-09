package com.cashu.me.liveintegration

import androidx.test.platform.app.InstrumentationRegistry
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.test.FullOnly
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

@FullOnly
class PaymentExtendedLocalMintTest : PaymentFixtureTest() {
    @Test fun cashuRequestFixedAndAmountlessHttpDelivery() = runBlocking {
        assertRequestDelivery("controlled")
    }

    // Runnable reproduction, excluded from the required manifest until CDK is fixed.
    @Test fun cashuRequestReceiverFeeRegression() = runBlocking {
        assumeTrue("Known CDK 0.18 receiver-fee regression; see CI/payment-tests/README.md",
            InstrumentationRegistry.getArguments().getString("cashu.paymentKnownRegressions") == "true")
        assertRequestDelivery("fees")
    }

    private suspend fun assertRequestDelivery(mint: String) {
        for (amount in listOf(21L, null)) {
            val payer = wallet(mint)
            val receiver = wallet(mint)
            payer.fund()
            val encoded = call("$root/request", "POST", buildJsonObject {
                put("target", "$fixture$root/receive")
                putJsonArray("mints") { add(payer.url) }
                if (amount != null) put("amount", amount)
            }).getValue("request").jsonPrimitive.content
            payer.gateway.payCashuPaymentRequest(encoded, if (amount == null) 21 else null, payer.url)
            val delivered = call("$root/received-token")
            assertEquals(id, delivered.getValue("id").jsonPrimitive.content)
            assertEquals("Payment request must include the receiver's redemption fee", 21,
                receiver.receive(delivered.getValue("token").jsonPrimitive.content))
            if (mint == "controlled") {
                assertEquals("A zero-fee request must debit exactly the requested amount", 79, payer.balance())
            } else {
                assertTrue(payer.balance() <= 79)
            }
        }
    }

    @Test fun cashuRequestDeliveryFailureLeavesReclaimableToken() = runBlocking {
        val payer = wallet("controlled")
        payer.fund()
        val encoded = call("$root/request", "POST", buildJsonObject {
            put("target", "$fixture$root/unavailable"); put("amount", 21)
        }).getValue("request").jsonPrimitive.content
        expectError("deliver") { payer.gateway.payCashuPaymentRequest(encoded, null, payer.url) }
        val operation = payer.gateway.listPendingSendOperationIds(payer.url).single()
        assertEquals(21, payer.gateway.revokePendingSend(payer.url, operation))
        assertEquals(100, payer.balance())
    }

    @Test fun repeatedFeePreviewReleasesReservedProofs() = runBlocking {
        val sender = wallet("controlled")
        sender.fund()
        repeat(3) { assertEquals(0, sender.gateway.estimateCashuPaymentRequestFee(80, sender.url)) }
        assertEquals(100, sender.balance())
        val recipient = wallet("controlled")
        assertEquals(100, recipient.receive(sender.send(100).token))
    }

    @Test fun multipleMintUnitsDoNotCrossCredit() = runBlocking {
        val payer = wallet("cdk")
        payer.fund(21)
        payer.gateway.ensureWallet(payer.url, "usd")
        val quote = payer.gateway.createMintQuote(125, PaymentMethodKind.Bolt11, payer.url, "usd")
        payer.awaitPaid(quote)
        assertEquals(125, payer.gateway.mintTokens(quote.id))
        val recipient = wallet("cdk")
        recipient.gateway.ensureWallet(recipient.url, "usd")
        val token = payer.gateway.sendEcashToken(25, null, null, payer.url, "usd")
        assertEquals(25, recipient.receive(token.token))
        assertEquals(21, payer.balance())
        assertEquals(100, payer.gateway.unitBalance(payer.url, "usd"))
        assertEquals(25, recipient.gateway.unitBalance(recipient.url, "usd"))
        assertEquals(0, recipient.balance())
    }

    @Test fun nwcPaymentLimitReplayAndBalance() = runBlocking {
        val payer = wallet("cdk")
        payer.fund()
        val relay = fixture.replace("http://", "ws://") + root + "/relay"
        val service = payer.gateway.createOrRestoreNwcService(payer.url, listOf(relay), ByteArray(64) { 1 }, null, 21_000u)
        service.start()
        try {
            fun request(method: String, invoice: String? = null, duplicate: Boolean = false) =
                call("$root/nwc", "POST", buildJsonObject {
                    put("uri", service.connectionUri); put("method", method); put("duplicate", duplicate)
                    if (invoice != null) putJsonObject("params") { put("invoice", invoice) }
                })
            assertEquals(100_000, request("get_balance").getValue("result").jsonObject.getValue("balance").jsonPrimitive.long)
            val rejected = request("pay_invoice", invoice(22))
            assertEquals("QUOTA_EXCEEDED", rejected.getValue("error").jsonObject.getValue("code").jsonPrimitive.content)
            assertEquals(100, payer.balance())
            val paid = request("pay_invoice", invoice(), true)
            assertNotNull(paid["result"])
            assertNull(paid["timeout"])
            val receipts = payer.gateway.listTransactions(mapOf(payer.url to listOf("sat"))).filter { it.type == com.cashu.me.Models.TransactionType.Outgoing }
            assertEquals(1, receipts.size)
            assertEquals(100, payer.balance() + 21 + receipts.single().fee)
            assertEquals(payer.balance() * 1000, request("get_balance").getValue("result").jsonObject.getValue("balance").jsonPrimitive.long)
            assertEquals(1, payer.gateway.listTransactions(mapOf(payer.url to listOf("sat"))).count {
                it.type == com.cashu.me.Models.TransactionType.Outgoing
            })
        } finally {
            service.stop()
            service.close()
        }
    }
}
