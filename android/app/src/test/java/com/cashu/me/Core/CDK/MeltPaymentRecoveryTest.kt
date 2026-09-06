package com.cashu.me.Core.CDK

import com.cashu.me.Core.Wallet.walletMessage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.cashudevkit.QuoteState
import org.junit.Assert.*
import org.junit.Test

class MeltPaymentRecoveryTest {
    @Test fun lostConfirmResponseResolvesPaidOrPendingWithoutRetry() = runBlocking {
        for (state in listOf(QuoteState.PAID, QuoteState.ISSUED, QuoteState.PENDING)) {
            assertEquals(state, resolveAmbiguousMelt("quote", "operation", { state },
                { fail("No recovery needed") }, { it }, { error("Must not release proofs") }))
        }
    }

    @Test fun statusFailureRunsSagaRecoveryThenChecksAgain() = runBlocking {
        var checks = 0
        var recoveries = 0
        val state = resolveAmbiguousMelt("quote", "operation",
            { if (++checks == 1) error("Lost response") else QuoteState.PAID },
            { recoveries++ }, { it }, { false })
        assertEquals(QuoteState.PAID, state)
        assertEquals(1, recoveries)
        assertEquals(2, checks)
    }

    @Test fun offlineMintBlocksRetryAndDoesNotClaimFailure() = runBlocking {
        try {
            resolveAmbiguousMelt<QuoteState>("quote", "operation", { error("offline") }, {}, { it }, { true })
            fail("Unknown status must block retry")
        } catch (error: MeltPaymentRecoveryException) {
            assertTrue(error.unresolved)
            assertTrue(error.walletMessage.isTerminal)
            assertEquals("Payment status unknown", error.walletMessage.title)
        }
    }

    @Test fun unpaidIsNotRetryableUntilAllReservationReadsSucceed() = runBlocking {
        for (reserved in listOf(true, false)) {
            try {
                resolveAmbiguousMelt("quote", "operation", { QuoteState.UNPAID }, {}, { it }, { !reserved })
                fail("UNPAID must require a fresh quote or further recovery")
            } catch (error: MeltPaymentRecoveryException) {
                assertEquals(reserved, error.unresolved)
                assertTrue(error.walletMessage.isTerminal)
            }
        }
        try {
            resolveAmbiguousMelt("quote", "operation", { QuoteState.UNPAID }, {}, { it }, { error("database unavailable") })
            fail("A failed read is not compensation")
        } catch (error: MeltPaymentRecoveryException) { assertTrue(error.unresolved) }
    }

    @Test fun cancellationPreservesCoroutineCancellation() = runBlocking {
        try {
            resolveAmbiguousMelt<QuoteState>("quote", "operation", { throw CancellationException() }, {}, { it }, { true })
            fail("Cancellation must propagate")
        } catch (_: CancellationException) { }
    }
}
