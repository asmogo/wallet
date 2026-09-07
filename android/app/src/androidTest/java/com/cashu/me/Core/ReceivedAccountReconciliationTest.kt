package com.cashu.me.Core

import com.cashu.me.Core.CDK.ReceiveRecoveryCandidate
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FixtureMode
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class ReceivedAccountReconciliationTest {
    @Test fun offlineRecoveryTracksOnceWithoutMetadataRedemptionOrAnotherAnnouncement() {
        AppTestFixture.launch(FixtureMode.SeededWithoutMint).use { fixture ->
            val manager = fixture.container.walletManager
            val fake = checkNotNull(fixture.fakeGateway)
            val store = fixture.container.walletStore
            runBlocking { manager.initialize() }
            val pending = PendingReceiveToken("approval", "cashu-awaiting-approval", 21, 1, "https://unapproved.example")
            store.savePendingReceiveTokens(listOf(pending))
            val fetchesBefore = fake.metadataFetches
            fake.receiveCandidates = listOf(ReceiveRecoveryCandidate("https://received.example", "sat"), ReceiveRecoveryCandidate("https://received.example", "usd"))
            fake.nextFailure = IllegalStateException("Offline")
            var announcements = 0
            runBlocking {
                val observer = launch(start = CoroutineStart.UNDISPATCHED) { manager.receivedPayments.collect { announcements++ } }
                manager.reconcileReceivedAccounts()
                manager.reconcileReceivedAccounts()
                observer.cancel()
            }
            assertEquals(listOf("https://received.example"), store.loadMints().map { it.url })
            assertEquals(fetchesBefore, fake.metadataFetches)
            assertEquals(0, announcements)
            assertEquals(listOf(pending), store.loadPendingReceiveTokens())
            assertEquals(setOf("sat", "usd"), store.loadMints().single().units.toSet())
            assertEquals(4, fake.receiveRecoveryCalls)
        }
    }
}
