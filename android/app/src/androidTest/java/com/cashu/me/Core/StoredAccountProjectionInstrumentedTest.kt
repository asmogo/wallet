package com.cashu.me.Core

import androidx.test.platform.app.InstrumentationRegistry
import com.cashu.me.Core.CDK.CdkWalletGateway
import com.cashu.me.Core.CDK.CdkWalletGatewayImpl
import com.cashu.me.Models.MintInfo
import com.cashu.me.test.fixtures.FakeWalletGateway
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.cashudevkit.*
import org.junit.Assert.*
import org.junit.Test

class StoredAccountProjectionInstrumentedTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun discontinuedCurrencyHistorySurvivesDatabaseReopenWithoutAnAdvertisedWallet() = runBlocking {
        val directory = File(context.cacheDir, UUID.randomUUID().toString()).apply { mkdirs() }
        val path = File(directory, "wallet.db").path
        val mint = MintUrl("https://offline.example")
        val gateway = CdkWalletGatewayImpl()
        try {
            val mnemonic = gateway.generateMnemonic()
            WalletSqliteDatabase(path).use { db ->
                db.addMint(mint, null)
                db.addTransaction(Transaction(
                    id = TransactionId("a".repeat(64)), mintUrl = mint,
                    direction = TransactionDirection.INCOMING, amount = Amount(250u), fee = Amount(0u),
                    unit = CurrencyUnit.Usd, ys = emptyList(), timestamp = 1u, memo = null,
                    metadata = emptyMap(), quoteId = null, paymentRequest = null, paymentProof = null,
                    paymentMethod = null, sagaId = null, status = TransactionStatus.COMPLETED,
                ))
            }
            gateway.openWalletRepository(mnemonic, path)
            val account = gateway.storedAccounts().single { it.unit == "usd" }
            assertEquals(0L, gateway.storedAccountBalance(account))
            assertEquals(0L, gateway.unitBalance(mint.url, "usd"))
            val store = WalletStore(context, "stored_accounts_" + UUID.randomUUID())
            val loader = WalletTransactionLoader(store, gateway)
            val mints = listOf(MintInfo(url = mint.url, units = listOf("sat")))
            assertEquals(listOf("usd"), loader.load(mints, false).transactions.map { it.unit })
            gateway.closeWalletRepository()
            gateway.openWalletRepository(mnemonic, path)
            assertEquals(listOf("usd"), loader.load(mints, false).transactions.map { it.unit })
        } finally {
            gateway.closeWalletRepository()
            directory.deleteRecursively()
        }
    }

    @Test fun failedHistoryReadPreservesAffectedAccountWhileRefreshingOthers() = runBlocking {
        val fake = FakeWalletGateway()
        fake.openWalletRepository("fixture", "unused")
        fake.ensureWallet("https://a.example", "usd")
        fake.ensureWallet("https://b.example", "sat")
        fun tx(id: String, mint: String, unit: String) = com.cashu.me.Models.WalletTransaction(
            id = id, amount = 10, type = com.cashu.me.Models.TransactionType.Incoming,
            kind = com.cashu.me.Models.TransactionKind.Ecash, dateEpochMillis = 1,
            status = com.cashu.me.Models.TransactionStatus.Completed, mintUrl = mint, unit = unit,
        )
        fake.addTransaction(tx("usd-old", "https://a.example", "usd"))
        val store = WalletStore(context, "history_failure_" + UUID.randomUUID())
        val mints = listOf(MintInfo("https://a.example"), MintInfo("https://b.example"))
        WalletTransactionLoader(store, fake).load(mints, false)
        fake.addTransaction(tx("sat-new", "https://b.example", "sat"))
        val failing = object : CdkWalletGateway by fake {
            override suspend fun listTransactions(unitsByMint: Map<String, List<String>>): List<com.cashu.me.Models.WalletTransaction> {
                if (unitsByMint.containsKey("https://a.example")) error("Storage unavailable")
                return fake.listTransactions(unitsByMint)
            }
        }
        val result = WalletTransactionLoader(store, failing).load(mints, false)
        assertEquals(setOf("usd-old", "sat-new"), result.transactions.map { it.id }.toSet())
    }
}
