package com.cashu.me.Core

import com.cashu.me.Core.CDK.ReceiveRecoveryCandidate
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FakeWalletGateway
import com.cashu.me.test.fixtures.FixtureMode
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class ReceivedAccountReconciliationTest {
    @Test fun removalSkipsRetainedProofsUntilTheMintIsAddedAgain() {
        AppTestFixture.launch(FixtureMode.SeededWithMint).use { fixture ->
            val manager = fixture.container.walletManager
            val fake = checkNotNull(fixture.fakeGateway)
            val store = fixture.container.walletStore
            val mint = store.loadMints().single()
            fake.receiveCandidates = listOf(ReceiveRecoveryCandidate(mint.url, "sat"))
            runBlocking {
                manager.removeMint(mint)
                manager.reconcileReceivedAccounts()
                manager.reconcileReceivedAccounts()
                assertTrue(store.isMintRemoved(mint.url))
                assertTrue(store.loadMints().isEmpty())
                assertEquals(0, fake.receiveRecoveryCalls)

                manager.addMint(mint.url)
                manager.reconcileReceivedAccounts()
                assertFalse(store.isMintRemoved(mint.url))
                assertEquals(listOf(mint.url), store.loadMints().map { it.url })
                assertEquals(1, fake.receiveRecoveryCalls)
            }
        }
    }

    @Test fun failedNativeRemovalDoesNotExcludeTheMint() {
        AppTestFixture.launch(FixtureMode.SeededWithMint).use { fixture ->
            val manager = fixture.container.walletManager
            val fake = checkNotNull(fixture.fakeGateway)
            val store = fixture.container.walletStore
            val mint = store.loadMints().single()
            runBlocking {
                fake.ensureWallet(mint.url, "usd")
                assertTrue(runCatching { manager.removeMint(mint) }.isFailure)
            }
            assertFalse(store.isMintRemoved(mint.url))
            assertEquals(listOf(mint.url), store.loadMints().map { it.url })
        }
    }

    @Test fun approvedReceiveAllowsRecoveryAfterALostResponseFromARemovedMint() {
        AppTestFixture.launch(FixtureMode.SeededWithMint).use { fixture ->
            val manager = fixture.container.walletManager
            val fake = checkNotNull(fixture.fakeGateway)
            val store = fixture.container.walletStore
            runBlocking {
                manager.removeMint(store.loadMints().single())
                fake.receiveCandidates = listOf(ReceiveRecoveryCandidate(FakeWalletGateway.TestMintUrl, "sat"))
                fake.nextFailure = IllegalStateException("Swap response lost")
                assertTrue(runCatching { manager.receiveTokens(FakeWalletGateway.DeterministicToken) }.isFailure)
            }
            assertFalse(store.isMintRemoved(FakeWalletGateway.TestMintUrl))
            assertEquals(listOf(FakeWalletGateway.TestMintUrl), store.loadMints().map { it.url })
            assertEquals(1, fake.receiveRecoveryCalls)
        }
    }

    @Test fun successfulReceiveEnrichesTheDurablePlaceholderWithoutLosingCurrencies() {
        val methods = listOf(PaymentMethodKind.Bolt11, PaymentMethodKind.Bolt12, PaymentMethodKind.Onchain)
        AppTestFixture.launch(FixtureMode.SeededWithoutMint, supportedMintMethods = methods).use { fixture ->
            val manager = fixture.container.walletManager
            val fake = checkNotNull(fixture.fakeGateway)
            val store = fixture.container.walletStore
            fake.receiveCandidates = listOf(ReceiveRecoveryCandidate(FakeWalletGateway.TestMintUrl, "usd"))
            runBlocking { manager.reconcileReceivedAccounts() }
            fake.onMetadataFetch = {
                val placeholder = store.loadMints().single()
                assertEquals("Unknown Mint", placeholder.name)
                assertEquals(setOf("sat", "usd"), placeholder.units.toSet())
            }
            val amount = runBlocking { manager.receiveTokens(FakeWalletGateway.DeterministicToken) }
            val enriched = store.loadMints().single()
            assertEquals(25L, amount)
            assertEquals("Nutshell UI Test Mint", enriched.name)
            assertEquals(methods, enriched.supportedMintMethods)
            assertEquals(setOf("sat", "usd"), enriched.units.toSet())
            assertEquals(25L, manager.state.value.balance)
            assertEquals(enriched, manager.state.value.activeMint)
        }
    }

    @Test fun metadataFailureKeepsASuccessfulReceiveAndItsPlaceholder() {
        AppTestFixture.launch(FixtureMode.SeededWithoutMint).use { fixture ->
            val manager = fixture.container.walletManager
            val fake = checkNotNull(fixture.fakeGateway)
            val store = fixture.container.walletStore
            fake.metadataFailure = IllegalStateException("Metadata offline")
            val amount = runBlocking { manager.receiveTokens(FakeWalletGateway.DeterministicToken) }
            assertEquals(25L, amount)
            assertEquals("Unknown Mint", store.loadMints().single().name)
            assertEquals(25L, manager.state.value.balance)
            assertTrue(fake.metadataFetches > 0)
        }
    }

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
