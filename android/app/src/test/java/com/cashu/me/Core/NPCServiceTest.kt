package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.coroutines.cancel
import org.cashudevkit.NpubCashQuote

class NPCServiceTest {
    @Test
    fun walletReplacementRestoresSeparateNpcPreferencesAndRuntimeState() = kotlinx.coroutines.runBlocking {
        val prefs = InMemorySharedPreferences()
        prefs.edit()
            .putBoolean(com.cashu.me.Core.Protocols.StorageKeys.npcEnabled, true)
            .putBoolean(com.cashu.me.Core.Protocols.StorageKeys.npcAutomaticClaim, false)
            .putString(com.cashu.me.Core.Protocols.StorageKeys.npcSelectedMint, "https://mint.example")
            .putLong(com.cashu.me.Core.Protocols.StorageKeys.npcLastCheck, 123L)
            .commit()
        val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.Unconfined)
        try {
            val service = NPCService(prefs, kotlinx.coroutines.flow.MutableStateFlow(SettingsState()), scope)
            service.pauseForWalletBoundary()
            val snapshot = service.snapshotWalletScopedData()
            service.resetForWalletBoundary()
            assertFalse(service.state.value.isEnabled)
            service.restoreWalletScopedData(snapshot)
            assertTrue(service.state.value.isEnabled)
            assertFalse(service.state.value.automaticClaim)
            assertEquals("https://mint.example", service.state.value.selectedMintUrl)
            assertEquals(123L, service.state.value.lastCheckEpochMillis)
        } finally { scope.cancel() }
    }

    @Test
    fun mapsCdkQuoteWithoutReimplementingTheWireFormat() {
        val quote = NPCService.fromCdkQuote(
            NpubCashQuote(
                id = "quote-1",
                amount = 21uL,
                unit = "sat",
                createdAt = 1_779_271_200uL,
                paidAt = 1_779_271_800uL,
                expiresAt = 1_779_273_000uL,
                mintUrl = "https://mint.example",
                request = "lnbc1invoice",
                state = "PAID",
                locked = true,
            ),
        )

        assertEquals("quote-1", quote.id)
        assertEquals(21, quote.amount)
        assertEquals("https://mint.example", quote.mintUrl)
        assertEquals("lnbc1invoice", quote.request)
        assertTrue(quote.isPaid)
        assertTrue(quote.locked)
        assertEquals(1_779_271_200L, quote.createdAtEpochSeconds)
        assertEquals(1_779_271_800L, quote.paidAtEpochSeconds)
        assertEquals(1_779_273_000L, quote.expiryEpochSeconds)
    }

    @Test
    fun mapsNullableCdkQuoteFields() {
        val quote = NPCService.fromCdkQuote(
            NpubCashQuote(
                id = "quote-2",
                amount = 42uL,
                unit = "sat",
                createdAt = 100uL,
                paidAt = null,
                expiresAt = null,
                mintUrl = null,
                request = null,
                state = null,
                locked = null,
            ),
        )

        assertEquals(42, quote.amount)
        assertEquals(null, quote.paidAtEpochSeconds)
        assertEquals(null, quote.expiryEpochSeconds)
        assertEquals(false, quote.locked)
    }

    @Test
    fun derivesStandardBip39Seed() {
        val mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        val expected =
            "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553" +
                "1f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"

        val seedHex = walletBip39Seed(mnemonic, passphrase = "TREZOR")
            .joinToString("") { "%02x".format(it) }

        assertEquals(expected, seedHex)
    }

    @Test
    fun paidQuotesForProcessingSkipsProcessedAndSortsOldestFirst() {
        val newest = NPCQuote(
            id = "newest",
            amount = 1,
            mintUrl = "https://mint.example",
            state = "PAID",
            locked = false,
            createdAtEpochSeconds = 30,
            paidAtEpochSeconds = 30,
        )
        val oldest = newest.copy(id = "oldest", paidAtEpochSeconds = 10)
        val processed = newest.copy(id = "processed", paidAtEpochSeconds = 1)
        val unpaid = newest.copy(id = "unpaid", state = "UNPAID", paidAtEpochSeconds = 0)

        val quotes = NPCService.paidQuotesForProcessing(
            quotes = listOf(newest, oldest, processed, unpaid),
            processedQuoteIds = setOf("processed"),
        )

        assertEquals(listOf("oldest", "newest"), quotes.map { it.id })
    }

    @Test
    fun periodicInvoiceChecksRequireBothPreferences() {
        assertTrue(
            NPCService.shouldRunPeriodicInvoiceChecks(
                isEnabled = true,
                isInitialized = true,
                checkIncomingInvoices = true,
                periodicallyCheckIncomingInvoices = true,
            ),
        )
        assertFalse(
            NPCService.shouldRunPeriodicInvoiceChecks(
                isEnabled = true,
                isInitialized = true,
                checkIncomingInvoices = false,
                periodicallyCheckIncomingInvoices = true,
            ),
        )
        assertFalse(
            NPCService.shouldRunPeriodicInvoiceChecks(
                isEnabled = true,
                isInitialized = true,
                checkIncomingInvoices = true,
                periodicallyCheckIncomingInvoices = false,
            ),
        )
        assertFalse(
            NPCService.shouldRunPeriodicInvoiceChecks(
                isEnabled = false,
                isInitialized = true,
                checkIncomingInvoices = true,
                periodicallyCheckIncomingInvoices = true,
            ),
        )
        assertFalse(
            NPCService.shouldRunPeriodicInvoiceChecks(
                isEnabled = true,
                isInitialized = false,
                checkIncomingInvoices = true,
                periodicallyCheckIncomingInvoices = true,
            ),
        )
    }
}
