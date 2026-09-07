package com.cashu.me.liveintegration

import androidx.test.platform.app.InstrumentationRegistry
import com.cashu.me.Core.CDK.CdkWalletGatewayImpl
import com.cashu.me.Core.CDK.ReceiveRecoveryCandidate
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class ReceiptRecoveryInstrumentedTest {
    private val args get() = InstrumentationRegistry.getArguments()
    private val mint get() = args.getString("cashu.receiptRecoveryMintUrl") ?: "http://127.0.0.1:3340"

    @Test fun completedReceiptBeforeTrackingSurvivesOfflineReopen() = runBlocking { exerciseReceipt(false) }
    @Test fun acceptedSwapWithLostResponseRecoversAfterReopenExactlyOnce() = runBlocking { exerciseReceipt(true) }

    private suspend fun exerciseReceipt(interrupt: Boolean) {
        assumeTrue(args.getString("cashu.nativeWalletLocalMintIntegration") == "true")
        control("reset")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, UUID.randomUUID().toString()).apply { mkdirs() }
        val sender = CdkWalletGatewayImpl()
        val receiver = CdkWalletGatewayImpl()
        try {
            sender.openWalletRepository(sender.generateMnemonic(), File(directory, "sender.db").path)
            sender.ensureWallet(mint)
            val quote = sender.createMintQuote(16, PaymentMethodKind.Bolt11, mint)
            for (attempt in 0..<40) {
                if (sender.checkMintQuote(quote.id).state == MintQuoteState.Paid) break
                delay(100)
            }
            sender.mintTokens(quote.id)
            val token = sender.sendEcashToken(16, null, null, mint).token
            val seed = receiver.generateMnemonic()
            val path = File(directory, "receiver.db").path
            receiver.openWalletRepository(seed, path)
            receiver.ensureWallet(mint)
            assertTrue("Preview and unapproved tokens provide no recovery evidence", receiver.receiveRecoveryCandidates().isEmpty())
            if (interrupt) control("interrupt-next-swap")
            val result = runCatching { receiver.receiveEcashToken(token) }
            assertEquals(interrupt, result.isFailure)
            if (!interrupt) assertEquals(16L, result.getOrThrow())
            receiver.closeWalletRepository()
            control("offline")
            receiver.openWalletRepository(seed, path)
            val candidates = receiver.receiveRecoveryCandidates()
            assertEquals(listOf(ReceiveRecoveryCandidate(mint, "sat")), candidates)
            if (!interrupt) assertEquals(16L, receiver.totalBalance(mint))
            control("reset")
            candidates.forEach { receiver.recoverReceiveAccount(it) }
            candidates.forEach { receiver.recoverReceiveAccount(it) }
            assertEquals(16L, receiver.totalBalance(mint))
            val transactions = receiver.listTransactions(mapOf(mint to listOf("sat")))
            assertEquals(1, transactions.size)
            assertEquals(com.cashu.me.Models.TransactionStatus.Completed, transactions.single().status)
        } finally {
            control("reset")
            sender.closeWalletRepository()
            receiver.closeWalletRepository()
            directory.deleteRecursively()
        }
    }

    private fun control(action: String) {
        val connection = (URL("$mint/__receipt_test/$action").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 5_000
            readTimeout = 5_000
        }
        try { assertEquals(200, connection.responseCode) } finally { connection.disconnect() }
    }
}
