package com.cashu.me.liveintegration

import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import com.cashu.me.Core.CDK.CdkWalletGatewayImpl
import com.cashu.me.Core.LightningRequestParser
import com.cashu.me.Core.NostrService
import com.cashu.me.Core.PaymentRequestBuilder
import com.cashu.me.Core.PaymentRequestDecodeResult
import com.cashu.me.Core.PaymentRequestDecoder
import com.cashu.me.Core.TokenParser
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import com.cashu.me.test.FullOnly

class NativeWalletLocalMintInstrumentedTest {
    private val args = InstrumentationRegistry.getArguments()
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val workDir = File(context.filesDir, "native-wallet-local-mint-matrix")
    private val nutshellMintUrl: String = args.getString("cashu.nutshellMintUrl") ?: "http://127.0.0.1:3338"
    private val cdkMintUrl: String = args.getString("cashu.cdkMintUrl") ?: "http://127.0.0.1:3339"
    private val bolt11MeltInvoice: String = args.getString("cashu.bolt11MeltInvoice") ?: STANDALONE_BOLT11_INVOICE

    @After
    fun cleanUp() {
        workDir.deleteRecursively()
    }

    @Test
    fun bolt12PaidButUnissuedQuoteRecoversAfterDatabaseReopen() = runBlocking {
        assumeNativeMatrixEnabled()
        assertMintEndpointReady(cdkMintUrl)
        workDir.deleteRecursively()
        workDir.mkdirs()

        val payer = TestWallet("bolt12-recovery")
        try {
            payer.open()
            payer.gateway.ensureWallet(cdkMintUrl)
            val quote = payer.gateway.createMintQuote(
                amount = null,
                method = PaymentMethodKind.Bolt12,
                mintUrl = cdkMintUrl,
                unit = "sat",
            )
            assertEquals(PaymentMethodKind.Bolt12, LightningRequestParser.parse(quote.request).method)

            val paid = quote.awaitPaid(payer.gateway)
            val outstanding = paid.amountPaid - paid.amountIssued
            assertTrue(outstanding > 0)
            val balanceBeforeRecovery = payer.gateway.totalBalance(cdkMintUrl)

            val payerMnemonic = payer.mnemonic
            payer.close()
            payer.open(payerMnemonic)

            assertTrue(payer.gateway.listUnissuedMintQuotes().any { it.id == paid.id })
            assertEquals(
                outstanding,
                payer.gateway.mintUnissuedQuotes(cdkMintUrl, "sat"),
            )
            val verified = payer.gateway.checkMintQuote(paid.id)
            assertEquals(verified.amountPaid, verified.amountIssued)
            assertEquals(
                balanceBeforeRecovery + outstanding,
                payer.gateway.totalBalance(cdkMintUrl),
            )
            assertEquals(0L, payer.gateway.mintUnissuedQuotes(cdkMintUrl, "sat"))

            // This is deliberately the process-death boundary over the same
            // durable database. A seed-only restore cannot discover a
            // mint-generated quote id or its NUT-20 signing-key association;
            // that requires an upstream/exported quote-backup format.
        } finally {
            payer.close()
        }
    }

    @Test
    fun foreignNfcChangeRemainsSpendableAfterDatabaseReopen() = runBlocking {
        assumeNativeMatrixEnabled()
        assertMintEndpointReady(nutshellMintUrl)
        assertMintEndpointReady(cdkMintUrl)
        workDir.mkdirs()
        val payer = TestWallet("nfc-payer")
        val receiver = TestWallet("nfc-receiver")
        try {
            payer.open()
            receiver.open()
            payer.gateway.ensureWallet(nutshellMintUrl)
            receiver.gateway.ensureWallet(cdkMintUrl)
            val quote = payer.gateway.createMintQuote(1_000, PaymentMethodKind.Bolt11, nutshellMintUrl, "sat")
            val paid = quote.awaitPaid(payer.gateway)
            payer.gateway.mintTokens(paid.id)
            val token = payer.gateway.sendEcashToken(1_000, null, null, nutshellMintUrl).token
            val result = receiver.gateway.settleForeignNfcToken(token, cdkMintUrl)
            val sourceChange = receiver.gateway.totalBalance(nutshellMintUrl)
            assertTrue("Conversion must retain unused fee reserve and overhead", sourceChange > 0)
            assertEquals(1_000L, result.amountReceived + sourceChange + result.feePaid)
            val seed = receiver.mnemonic
            receiver.close()
            receiver.open(seed)
            assertEquals(sourceChange, receiver.gateway.totalBalance(nutshellMintUrl))
            assertEquals(result.amountReceived, receiver.gateway.totalBalance(cdkMintUrl))
            val changeToken = receiver.gateway.sendEcashToken(sourceChange, null, null, nutshellMintUrl)
            assertEquals(sourceChange, payer.gateway.receiveEcashToken(changeToken.token))
        } finally {
            payer.close()
            receiver.close()
        }
    }

    @FullOnly
    @Test
    fun nativeCdkWalletMatrixAgainstLocalMints() = runBlocking {
        assumeNativeMatrixEnabled()
        assertMintEndpointReady(nutshellMintUrl)
        assertMintEndpointReady(cdkMintUrl)
        workDir.deleteRecursively()
        workDir.mkdirs()

        val payer = TestWallet("payer")
        val receiver = TestWallet("receiver")
        val restored = TestWallet("restored")
        var step = "open wallets"
        try {
            payer.open()
            receiver.open()

            step = "Nutshell mint info"
            payer.gateway.ensureWallet(nutshellMintUrl)
            val nutshellInfo = payer.gateway.fetchMintInfo(nutshellMintUrl)
            assertNotNull(nutshellInfo)
            assertTrue(nutshellInfo!!.supportedMintMethods.orEmpty().contains(PaymentMethodKind.Bolt11))

            step = "Nutshell BOLT11 mint"
            val paidQuote = payer.gateway.createMintQuote(
                amount = 21,
                method = PaymentMethodKind.Bolt11,
                mintUrl = nutshellMintUrl,
                unit = "sat",
            ).awaitPaid(payer.gateway)
            assertEquals(PaymentMethodKind.Bolt11, LightningRequestParser.parse(paidQuote.request).method)
            assertEquals(21L, payer.gateway.mintTokens(paidQuote.id))
            assertEquals(21L, payer.gateway.totalBalance(nutshellMintUrl))

            step = "Nutshell P2PK receive"
            val p2pk = randomP2PKKey()
            val locked = payer.gateway.sendEcashToken(
                amount = 4,
                memo = "native matrix",
                p2pkPubkey = p2pk.publicKey,
                mintUrl = nutshellMintUrl,
                unit = "sat",
            )
            assertTrue(TokenParser.isCashuToken(locked.token))
            assertEquals(listOf(p2pk.publicKey), TokenParser.p2pkPubkeys(locked.token))
            assertEquals(4L, receiver.gateway.receiveEcashToken(locked.token, listOf(p2pk.privateKeyHex)))
            assertEquals(4L, receiver.gateway.totalBalance(nutshellMintUrl))

            step = "Nutshell restore"
            restored.open(receiver.mnemonic)
            val restoreResult = restored.gateway.restoreMint(nutshellMintUrl)
            assertTrue(restoreResult.unspent >= 4L)
            assertTrue(restored.gateway.totalBalance(nutshellMintUrl) >= 4L)

            step = "Nutshell BOLT11 melt"
            val meltQuote = payer.gateway.createMeltQuote(
                request = bolt11MeltInvoice,
                amountSats = null,
                preferredMintURL = nutshellMintUrl,
            )
            val melt = payer.gateway.meltTokens(meltQuote.id, nutshellMintUrl).result
            assertEquals(PaymentMethodKind.Bolt11, melt.paymentMethod)
            assertTrue(melt.amount > 0)
            assertTrue(payer.gateway.totalBalance(nutshellMintUrl) < 17L)

            step = "CDK mint info"
            payer.gateway.ensureWallet(cdkMintUrl)
            val cdkInfo = payer.gateway.fetchMintInfo(cdkMintUrl)
            assertNotNull(cdkInfo)
            assertTrue(cdkInfo!!.supportedMintMethods.orEmpty().contains(PaymentMethodKind.Bolt12))
            assertTrue(cdkInfo.supportedMintMethods.orEmpty().contains(PaymentMethodKind.Onchain))
            assertTrue(cdkInfo.effectiveMintUnits.contains("usd"))

            step = "CDK BOLT11 sat mint"
            val cdkSatQuote = payer.gateway.createMintQuote(
                amount = 9,
                method = PaymentMethodKind.Bolt11,
                mintUrl = cdkMintUrl,
                unit = "sat",
            ).awaitPaid(payer.gateway)
            assertEquals(9L, payer.gateway.mintTokens(cdkSatQuote.id))
            assertTrue(payer.gateway.totalBalance(cdkMintUrl) >= 9L)

            step = "CDK plain token receive"
            val cdkPlain = payer.gateway.sendEcashToken(
                amount = 2,
                memo = "native matrix cdk plain",
                p2pkPubkey = null,
                mintUrl = cdkMintUrl,
                unit = "sat",
            )
            assertTrue(TokenParser.isCashuToken(cdkPlain.token))
            assertFalse(payer.gateway.checkTokenSpendable(cdkPlain.token, cdkMintUrl))
            assertEquals(2L, receiver.gateway.receiveEcashToken(cdkPlain.token))

            step = "CDK P2PK receive"
            val cdkP2pk = randomP2PKKey()
            val cdkLocked = payer.gateway.sendEcashToken(
                amount = 4,
                memo = "native matrix cdk",
                p2pkPubkey = cdkP2pk.publicKey,
                mintUrl = cdkMintUrl,
                unit = "sat",
            )
            assertTrue(TokenParser.isCashuToken(cdkLocked.token))
            assertEquals(listOf(cdkP2pk.publicKey), TokenParser.p2pkPubkeys(cdkLocked.token))
            assertEquals(4L, receiver.gateway.receiveEcashToken(cdkLocked.token, listOf(cdkP2pk.privateKeyHex)))
            assertTrue(receiver.gateway.totalBalance(cdkMintUrl) >= 6L)

            step = "CDK restore"
            val cdkRestoreResult = restored.gateway.restoreMint(cdkMintUrl)
            assertTrue(cdkRestoreResult.unspent >= 4L)
            assertTrue(restored.gateway.totalBalance(cdkMintUrl) >= 4L)

            step = "CDK BOLT11 usd mint"
            val usdQuote = payer.gateway.createMintQuote(
                amount = 125,
                method = PaymentMethodKind.Bolt11,
                mintUrl = cdkMintUrl,
                unit = "usd",
            ).awaitPaid(payer.gateway)
            assertEquals("usd", usdQuote.unit)
            assertEquals(125L, payer.gateway.mintTokens(usdQuote.id))
            assertTrue(payer.gateway.unitBalance(cdkMintUrl, "usd") >= 125L)

            step = "CDK BOLT12 quote"
            val bolt12 = payer.gateway.createMintQuote(
                amount = null,
                method = PaymentMethodKind.Bolt12,
                mintUrl = cdkMintUrl,
                unit = "sat",
            )
            assertEquals(PaymentMethodKind.Bolt12, LightningRequestParser.parse(bolt12.request).method)

            step = "CDK BOLT12 paid-but-unissued restart recovery"
            val paidBolt12 = bolt12.awaitPaid(payer.gateway)
            val outstandingBolt12 = paidBolt12.amountPaid - paidBolt12.amountIssued
            assertTrue(outstandingBolt12 > 0)
            val balanceBeforeRecovery = payer.gateway.totalBalance(cdkMintUrl)

            // Reopen the same native database before issuing. This is the app
            // process-death boundary that previously left a paid quote behind.
            // It is not a seed-only restore into an empty database: NUT-09
            // cannot discover the mint-generated quote id, and BOLT12 issuance
            // also needs the stored NUT-20 signing-key association. That needs
            // a CDK/exported quote-backup format before it can be tested here.
            val payerMnemonic = payer.mnemonic
            payer.close()
            payer.open(payerMnemonic)
            assertTrue(
                payer.gateway.listUnissuedMintQuotes().any { it.id == paidBolt12.id },
            )
            assertEquals(
                outstandingBolt12,
                payer.gateway.mintUnissuedQuotes(cdkMintUrl, "sat"),
            )
            val verifiedBolt12 = payer.gateway.checkMintQuote(paidBolt12.id)
            assertEquals(verifiedBolt12.amountPaid, verifiedBolt12.amountIssued)
            assertEquals(
                balanceBeforeRecovery + outstandingBolt12,
                payer.gateway.totalBalance(cdkMintUrl),
            )
            assertEquals(0L, payer.gateway.mintUnissuedQuotes(cdkMintUrl, "sat"))

            step = "CDK on-chain quote"
            val onchain = payer.gateway.createMintQuote(
                amount = 5,
                method = PaymentMethodKind.Onchain,
                mintUrl = cdkMintUrl,
                unit = "sat",
            )
            assertEquals(PaymentMethodKind.Onchain, onchain.paymentMethod)
            assertTrue(onchain.request.startsWith("bcrt", ignoreCase = true))

            step = "Cashu payment request decode"
            val cashuRequest = PaymentRequestBuilder.build(
                id = "native-wallet-local-matrix",
                amount = 3,
                unit = "sat",
                mints = listOf(cdkMintUrl),
                description = "Native Android local mint matrix",
                nostrPubkeyHex = p2pk.publicKey.drop(2),
                relays = emptyList(),
            )
            val decoded = PaymentRequestDecoder.decode(
                cashuRequest,
                includeCashuPaymentRequests = true,
            ) as? PaymentRequestDecodeResult.CashuPaymentRequest
            assertNotNull(decoded)
            assertEquals(3L, decoded!!.summary.amount)
            assertEquals(listOf(cdkMintUrl), decoded.summary.mints)
        } catch (throwable: Throwable) {
            throw AssertionError("Native local-mint matrix failed during $step.", throwable)
        } finally {
            payer.close()
            receiver.close()
            restored.close()
        }
    }

    private fun assumeNativeMatrixEnabled() {
        assumeTrue(
            "Run with cashu.nativeWalletLocalMintIntegration=true to enable native wallet local-mint coverage.",
            args.getString("cashu.nativeWalletLocalMintIntegration") == "true",
        )
    }

    private fun assertMintEndpointReady(mintUrl: String) {
        val connection = (URL("$mintUrl/v1/info").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 2_000
            readTimeout = 2_000
        }
        try {
            assertTrue("Mint endpoint is not ready: $mintUrl", connection.responseCode in 200..299)
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun MintQuoteInfo.awaitPaid(gateway: CdkWalletGatewayImpl): MintQuoteInfo {
        var current = this
        if (current.state == MintQuoteState.Paid || current.state == MintQuoteState.Issued) return current
        repeat(20) {
            current = runCatching {
                gateway.checkMintQuote(current.id)
            }.getOrElse { error ->
                if (error.message?.contains("mint quote already paid", ignoreCase = true) == true) {
                    current.copy(state = MintQuoteState.Paid)
                } else {
                    throw error
                }
            }
            if (current.state == MintQuoteState.Paid || current.state == MintQuoteState.Issued) return current
            delay(250)
        }
        error("Mint quote ${current.id} did not become paid; last state=${current.state}")
    }

    private fun randomP2PKKey(): P2PKKey {
        val random = SecureRandom()
        while (true) {
            val bytes = ByteArray(32).also(random::nextBytes)
            val privateKeyHex = bytes.joinToString("") { "%02x".format(it) }
            val publicKeyHex = runCatching { NostrService.publicKeyHex(privateKeyHex) }.getOrNull() ?: continue
            return P2PKKey(privateKeyHex = privateKeyHex, publicKey = "02$publicKeyHex")
        }
    }

    private inner class TestWallet(label: String) {
        val gateway = CdkWalletGatewayImpl()
        var mnemonic: String = ""
            private set
        private val database = File(workDir, "$label.db")

        suspend fun open(existingMnemonic: String? = null) {
            gateway.initializeLogging("warn")
            mnemonic = existingMnemonic ?: gateway.generateMnemonic()
            gateway.openWalletRepository(mnemonic, database.absolutePath)
        }

        suspend fun close() {
            gateway.closeWalletRepository()
        }
    }

    private data class P2PKKey(
        val privateKeyHex: String,
        val publicKey: String,
    )

    private companion object {
        const val STANDALONE_BOLT11_INVOICE =
            "lnbc30n1p4yuxg4pp5zarhytpl8gq9j6rm5lezx3zcduwxdfq9n7h4zgqajgjwpsze7e5qdp2g9hxgun0d9jzqmnpw35hvefqd4shgunf0qsx6etvwssp5qfx3ut73g4uj4jyf6vp4dfr6duqerykycqsq0rgz6k0dx0uxf3fs9qypqsqxqxfvcqcq3n0nce8ju867gmhvd8kejujxyrsz4fh8af2yghef9853az3ekxz4l3mev8p6rldfceh75kxal4ejva6cur7dep6dzw5wz4gq29zt6lcpkwmv3l"
    }
}
