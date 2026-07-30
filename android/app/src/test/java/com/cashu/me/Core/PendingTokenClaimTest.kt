package com.cashu.me.Core

import com.cashu.me.Models.PendingToken
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingTokenClaimTest {
    @Test
    fun manualCheckIsOnlyOfferedForPendingTokenWhenAutomaticChecksAreDisabled() {
        val pending = pendingToken()

        assertTrue(shouldOfferManualClaimCheck(automaticChecksEnabled = false, pending))
        assertFalse(shouldOfferManualClaimCheck(automaticChecksEnabled = true, pending))
        assertFalse(shouldOfferManualClaimCheck(automaticChecksEnabled = false, pendingToken = null))
    }

    @Test
    fun resolvesMergedHistoryRowByEncodedTokenWhenCdkReplacesItsId() {
        val pending = pendingToken()
        val mergedRow = pendingTransaction(id = "cdk-transaction-id", token = pending.token)

        assertEquals(pending, pendingSentTokenFor(mergedRow, listOf(pending)))
    }

    @Test
    fun doesNotResolveIncomingOrCompletedEcashRows() {
        val pending = pendingToken()

        assertEquals(
            null,
            pendingSentTokenFor(
                pendingTransaction(token = pending.token).copy(type = TransactionType.Incoming),
                listOf(pending),
            ),
        )
        assertEquals(
            null,
            pendingSentTokenFor(
                pendingTransaction(token = pending.token).copy(status = TransactionStatus.Completed),
                listOf(pending),
            ),
        )
    }

    @Test
    fun distinguishesClaimedNotClaimedAndRetryableFailure() = runBlocking {
        assertSame(
            PendingTokenClaimCheckResult.Claimed,
            runPendingTokenClaimCheck { true },
        )
        assertSame(
            PendingTokenClaimCheckResult.NotClaimed,
            runPendingTokenClaimCheck { false },
        )

        val failed = runPendingTokenClaimCheck {
            throw IllegalStateException("network connection failed")
        } as PendingTokenClaimCheckResult.Failed
        assertEquals("Couldn't reach the mint. Check your connection and try again.", failed.message.text)
        assertTrue(failed.message.isRetryable)
    }

    @Test(expected = CancellationException::class)
    fun cancellationIsNotConvertedIntoARetryMessage() {
        runBlocking {
            runPendingTokenClaimCheck { throw CancellationException("screen closed") }
        }
    }

    private fun pendingToken() = PendingToken(
        tokenId = "local-pending-id",
        token = "cashuBpending",
        amount = 42,
        fee = 1,
        dateEpochMillis = 100,
        mintUrl = "https://mint.example.com",
    )

    private fun pendingTransaction(
        id: String = "local-pending-id",
        token: String,
    ) = WalletTransaction(
        id = id,
        amount = 42,
        type = TransactionType.Outgoing,
        kind = TransactionKind.Ecash,
        dateEpochMillis = 100,
        status = TransactionStatus.Pending,
        mintUrl = "https://mint.example.com",
        token = token,
        isPendingToken = true,
    )
}
