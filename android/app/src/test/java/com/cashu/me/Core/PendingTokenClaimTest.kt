package com.cashu.me.Core

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
    fun manualCheckIsOnlyOfferedForPendingSentTokenWhenAutomaticChecksAreDisabled() {
        val pending = pendingTransaction(token = "cashuBpending")

        assertTrue(shouldOfferManualClaimCheck(automaticChecksEnabled = false, pending))
        assertFalse(shouldOfferManualClaimCheck(automaticChecksEnabled = true, pending))
        assertFalse(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled = false,
                transaction = pending.copy(status = TransactionStatus.Completed),
            ),
        )
    }

    @Test
    fun isPendingSentTokenMatchesOnlyUnclaimedOutgoingEcash() {
        assertTrue(isPendingSentToken(pendingTransaction(token = "cashuBpending")))

        // Without the token string the row is not actionable (no QR/Copy).
        assertFalse(isPendingSentToken(pendingTransaction(token = null)))
        assertFalse(
            isPendingSentToken(pendingTransaction(token = "cashuBpending").copy(type = TransactionType.Incoming)),
        )
        assertFalse(
            isPendingSentToken(
                pendingTransaction(token = "cashuBpending").copy(status = TransactionStatus.Completed),
            ),
        )
        assertFalse(
            isPendingSentToken(
                pendingTransaction(token = "cashuBpending").copy(kind = TransactionKind.Lightning),
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

    private fun pendingTransaction(
        id: String = "cdk-transaction-id",
        token: String?,
    ) = WalletTransaction(
        id = id,
        amount = 42,
        type = TransactionType.Outgoing,
        kind = TransactionKind.Ecash,
        dateEpochMillis = 100,
        status = TransactionStatus.Pending,
        mintUrl = "https://mint.example.com",
        token = token,
        sagaId = "operation-id",
    )
}
