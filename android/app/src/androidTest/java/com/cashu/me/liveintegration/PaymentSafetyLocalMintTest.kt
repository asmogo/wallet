package com.cashu.me.liveintegration

import androidx.test.platform.app.InstrumentationRegistry
import com.cashu.me.Core.CDK.CdkWalletGatewayImpl
import com.cashu.me.Core.NostrService
import com.cashu.me.Models.MeltQuoteState
import com.cashu.me.Models.MeltSettlement
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

/** Production native gateway, real SQLite and mint proofs; only transport is controlled. */
open class PaymentFixtureTest {
    private val args = InstrumentationRegistry.getArguments()
    lateinit var fixture: String
    lateinit var id: String
    private val wallets = mutableListOf<TestWallet>()
    private val directory = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "payments-${UUID.randomUUID()}")
    val root get() = "/sessions/$id"

    @Before fun setupFixture() {
        assumeTrue("Enable the local payment suite", args.getString("cashu.paymentFixtures") == "true")
        fixture = requireNotNull(args.getString("cashu.paymentFixtureUrl")) { "Payment fixture URL is required" }
        id = call("/sessions", "POST").getValue("id").jsonPrimitive.content
        directory.mkdirs()
    }

    @After fun closeFixture() = runBlocking {
        wallets.forEach { it.gateway.closeWalletRepository() }
        if (::id.isInitialized) call(root, "DELETE")
        directory.deleteRecursively()
        Unit
    }

    fun call(path: String, method: String = "GET", body: JsonObject? = null): JsonObject {
        val connection = (URL(fixture + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 10_000
            readTimeout = 15_000
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        try {
            if (body != null) connection.outputStream.use { it.write(body.toString().toByteArray()) }
            check(connection.responseCode in 200..299) { "Fixture request failed: $path (${connection.responseCode})" }
            return Json.parseToJsonElement(connection.inputStream.bufferedReader().use { it.readText() }).jsonObject
        } finally { connection.disconnect() }
    }

    fun mintUrl(mint: String) = "$fixture$root/mint/$mint"
    suspend fun wallet(mint: String): TestWallet = TestWallet(mint).also { it.open(); wallets += it }

    inner class TestWallet(val mint: String) {
        var gateway = CdkWalletGatewayImpl()
        val url = mintUrl(mint)
        private val path = File(directory, "${UUID.randomUUID()}.db").absolutePath
        private lateinit var seed: String
        suspend fun open() {
            gateway.initializeLogging("warn")
            if (!::seed.isInitialized) seed = gateway.generateMnemonic()
            gateway.openWalletRepository(seed, path)
            gateway.ensureWallet(url)
        }
        suspend fun reopen() {
            gateway.closeWalletRepository()
            gateway = CdkWalletGatewayImpl()
            open()
        }
        suspend fun balance() = gateway.totalBalance(url)
        suspend fun quote(amount: Long) = gateway.createMintQuote(amount, PaymentMethodKind.Bolt11, url, "sat")
        suspend fun pay(quote: MintQuoteInfo): MintQuoteInfo {
            if (mint in listOf("controlled", "fees")) {
                call("$root/pay/$mint", "POST", buildJsonObject { put("invoice", quote.request) })
            }
            return awaitPaid(quote)
        }
        suspend fun awaitPaid(quote: MintQuoteInfo): MintQuoteInfo {
            repeat(80) {
                val current = gateway.checkMintQuote(quote.id)
                if (current.state == MintQuoteState.Paid || current.state == MintQuoteState.Issued) return current
                delay(100)
            }
            error("Mint quote did not become paid")
        }
        suspend fun fund(amount: Long = 100) { assertEquals(amount, gateway.mintTokens(pay(quote(amount)).id)) }
        suspend fun send(amount: Long, key: String? = null) = gateway.sendEcashToken(amount, "Payment test", key, url)
        suspend fun receive(token: String, keys: List<String> = emptyList()) = gateway.receiveEcashToken(token, keys)
    }

    fun invoice(amount: Long = 21, script: JsonObject? = null): String = call("$root/invoice", "POST", buildJsonObject {
        put("amount", amount)
        if (script != null) put("description", script.toString())
    }).getValue("invoice").jsonPrimitive.content

    fun arm(path: String, action: String, method: String = "POST", count: Int = 1) {
        call("$root/faults", "POST", buildJsonObject {
            put("path", path); put("action", action); put("method", method); put("remaining", count)
        })
    }

    suspend fun expectError(vararg fragments: String, operation: suspend () -> Unit) {
        val failure = runCatching { operation() }.exceptionOrNull()
        assertNotNull("Expected payment rejection", failure)
        val message = failure.toString().lowercase()
        assertTrue("Unexpected rejection: $failure", fragments.any { message.contains(it.lowercase()) })
    }
}

class PaymentSafetyLocalMintTest : PaymentFixtureTest() {
    @Test fun controlledQuoteRequiresPaymentAndIssuesOnlyOnce() = runBlocking {
        val wallet = wallet("controlled")
        val quote = wallet.quote(21)
        assertEquals(MintQuoteState.Unpaid, wallet.gateway.checkMintQuote(quote.id).state)
        assertEquals(0, wallet.balance())
        expectError("not paid", "unpaid", "20001", "Amount undefined") { wallet.gateway.mintTokens(quote.id) }
        wallet.gateway.recoverIncompleteSagas(wallet.url)
        wallet.pay(quote)
        assertEquals(21, wallet.gateway.mintTokens(quote.id))
        assertEquals(MintQuoteState.Issued, wallet.gateway.checkMintQuote(quote.id).state)
        assertEquals(0, wallet.gateway.mintUnissuedQuotes(wallet.url, "sat"))
        assertEquals(21, wallet.balance())
    }

    @Test fun bolt11InternalAndExternalPaymentsConserveBalanceAndPersistReceipt() = runBlocking {
        for (mint in listOf("controlled", "cdk")) {
            val payer = wallet(mint)
            val recipient = wallet(mint)
            payer.fund()
            val incoming = if (mint == "controlled") recipient.quote(21) else null
            val quote = payer.gateway.createMeltQuote(incoming?.request ?: invoice(), null, payer.url)
            // Nutshell 0.20.1 returns PENDING before persisting its async task.
            if (mint == "controlled") arm("/v1/melt/quote/bolt11/", "delay", "GET")
            val result = payer.gateway.meltTokens(quote.id, payer.url).result
            assertEquals(MeltSettlement.Settled, result.settlement)
            assertEquals(21, result.amount)
            assertEquals(100 - 21 - result.feePaid, payer.balance())
            payer.reopen()
            val history = payer.gateway.listTransactions(mapOf(payer.url to listOf("sat"))).filter { it.quoteId == quote.id }
            assertEquals(1, history.size)
            assertEquals(21, history.single().amount)
            assertEquals(result.feePaid, history.single().fee)
            if (incoming != null) {
                recipient.awaitPaid(incoming)
                assertEquals(21, recipient.gateway.mintTokens(incoming.id))
            }
        }
    }

    @Test fun lostMeltResponseRecoversWithoutSecondDebit() = runBlocking {
        val payer = wallet("cdk")
        payer.fund()
        val quote = payer.gateway.createMeltQuote(invoice(), null, payer.url)
        arm("/v1/melt/bolt11", "lose_response")
        runCatching { payer.gateway.meltTokens(quote.id, payer.url) }
        payer.gateway.recoverIncompleteSagas(payer.url)
        assertEquals(MeltQuoteState.Paid, payer.gateway.checkMeltQuoteStatus(quote.id, payer.url).state)
        val after = payer.balance()
        assertTrue(after < 100)
        payer.reopen()
        payer.gateway.recoverIncompleteSagas(payer.url)
        assertEquals(after, payer.balance())
        val receipts = payer.gateway.listTransactions(mapOf(payer.url to listOf("sat"))).filter { it.quoteId == quote.id }
        assertEquals(1, receipts.size)
        assertEquals(100, after + 21 + receipts.single().fee)
        val records = call(root).getValue("requests").jsonArray
        assertTrue(records.any { it.jsonObject["fault"]?.jsonPrimitive?.contentOrNull == "lose_response" && it.jsonObject["forwarded"]?.jsonPrimitive?.boolean == true })
    }

    @Test fun lostMintResponseRecoversPaidQuoteExactlyOnce() = runBlocking {
        val wallet = wallet("controlled")
        val quote = wallet.pay(wallet.quote(42))
        arm("/v1/mint/bolt11", "lose_response")
        runCatching { wallet.gateway.mintTokens(quote.id) }
        wallet.reopen()
        wallet.gateway.recoverIncompleteSagas(wallet.url)
        wallet.gateway.mintUnissuedQuotes(wallet.url, "sat")
        assertEquals(42, wallet.balance())
        assertEquals(0, wallet.gateway.mintUnissuedQuotes(wallet.url, "sat"))
        assertEquals(1, wallet.gateway.listTransactions(mapOf(wallet.url to listOf("sat"))).count { it.quoteId == quote.id })
        assertTrue(call(root).getValue("requests").jsonArray.any {
            it.jsonObject["fault"]?.jsonPrimitive?.contentOrNull == "lose_response" &&
                it.jsonObject["forwarded"]?.jsonPrimitive?.boolean == true
        })
    }

    @Test fun insufficientFundsAndOfflineQuoteDoNotDebit() = runBlocking {
        val wallet = wallet("controlled")
        wallet.fund()
        val quote = wallet.gateway.createMeltQuote(invoice(101), null, wallet.url)
        expectError("insufficient", "not enough", "Payment status is unknown") { wallet.gateway.meltTokens(quote.id, wallet.url) }
        arm("/v1/melt/quote/bolt11", "reject")
        expectError("503", "unavailable", "http") { wallet.gateway.createMeltQuote(invoice(), null, wallet.url) }
        assertEquals(100, wallet.balance())
        val recipient = wallet("controlled")
        assertEquals(100, recipient.receive(wallet.send(100).token))
    }

    @Test fun backendFailureReturnsSpendableFunds() = runBlocking {
        val payer = wallet("cdk")
        payer.fund()
        val request = invoice(script = buildJsonObject {
            put("pay_invoice_state", "UNPAID"); put("check_payment_state", "UNPAID")
            put("pay_err", true); put("check_err", false)
        })
        val quote = payer.gateway.createMeltQuote(request, null, payer.url)
        runCatching { payer.gateway.meltTokens(quote.id, payer.url) }
        payer.gateway.recoverIncompleteSagas(payer.url)
        assertEquals(100, payer.balance())
        val receiver = wallet("cdk")
        assertEquals(100, receiver.receive(payer.send(100).token))
    }

    @Test fun paidBolt11RecoversAfterDatabaseReopenExactlyOnce() = runBlocking {
        val wallet = wallet("controlled")
        val quote = wallet.pay(wallet.quote(42))
        wallet.reopen()
        assertEquals(42, wallet.gateway.mintUnissuedQuotes(wallet.url, "sat"))
        assertEquals(0, wallet.gateway.mintUnissuedQuotes(wallet.url, "sat"))
        assertEquals(1, wallet.gateway.listTransactions(mapOf(wallet.url to listOf("sat"))).count { it.quoteId == quote.id })
    }

    @Test fun ecashClaimAfterReopenCannotBeRevokedOrReceivedTwice() = runBlocking {
        val sender = wallet("controlled")
        val receiver = wallet("controlled")
        sender.fund()
        val token = sender.send(21).token
        val operation = sender.gateway.listPendingSendOperationIds(sender.url).single()
        sender.reopen()
        assertTrue(sender.gateway.listPendingSendOperationIds(sender.url).contains(operation))
        assertEquals(21, receiver.receive(token))
        assertTrue(sender.gateway.checkPendingSendClaimed(sender.url, operation))
        expectError("spent", "claimed", "not found", "completed", "unknown") { sender.gateway.revokePendingSend(sender.url, operation) }
        expectError("spent", "already", "11001") { receiver.receive(token) }
        assertEquals(79, sender.balance())
        assertEquals(21, receiver.balance())
    }

    @Test fun revokeUnclaimedTokenRestoresSpendability() = runBlocking {
        val sender = wallet("controlled")
        val receiver = wallet("controlled")
        sender.fund()
        val token = sender.send(21).token
        val operation = sender.gateway.listPendingSendOperationIds(sender.url).single()
        assertEquals(21, sender.gateway.revokePendingSend(sender.url, operation))
        expectError("spent", "already", "11001") { receiver.receive(token) }
        assertEquals(100, receiver.receive(sender.send(100).token))
    }

    @Test fun feeChargingMintMaxSendAndReceiveConserveValue() = runBlocking {
        val sender = wallet("fees")
        val receiver = wallet("fees")
        sender.fund()
        val sent = sender.send(100)
        assertEquals(0, sent.fee)
        val fee = receiver.gateway.calculateReceiveFee(sent.token)
        assertTrue(fee > 0)
        val received = receiver.receive(sent.token)
        assertEquals(100 - fee, received)
        assertEquals(0, sender.balance())
        assertEquals(received, receiver.balance())
    }

    @Test fun p2pkWrongKeyThenCorrectKeyOnBothMints() = runBlocking {
        val privateKey = "0".repeat(63) + "1"
        val publicKey = "02" + NostrService.publicKeyHex(privateKey)
        for (mint in listOf("nutshell", "cdk")) {
            val sender = wallet(mint)
            val receiver = wallet(mint)
            sender.fund()
            val token = sender.send(21, publicKey).token
            expectError("key", "signature", "witness", "sign", "p2pk") { receiver.receive(token, listOf("0".repeat(63) + "2")) }
            assertEquals(0, receiver.balance())
            assertEquals(21, receiver.receive(token, listOf(privateKey)))
        }
    }

    @Test fun concurrentReceiversCannotDoubleCredit() = runBlocking {
        val sender = wallet("controlled")
        val a = wallet("controlled")
        val b = wallet("controlled")
        sender.fund()
        val token = sender.send(21).token
        val results = coroutineScope {
            val first = async { runCatching { a.receive(token) }.isSuccess }
            val second = async { runCatching { b.receive(token) }.isSuccess }
            listOf(first.await(), second.await())
        }
        assertEquals(1, results.count { it })
        assertEquals(21, a.balance() + b.balance())
    }
}
