package com.cashu.me.ui.restore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RestoreWalletFailureMessageTest {
    @Test
    fun mapsCdkNetworkFailureToWalletFacingCopy() {
        val phase = restoreMintFailurePhase(
            IllegalStateException(
                "FfiError.Cdk(code=11001, errorMessage=Connection refused)",
            ),
        )

        assertEquals(
            "Couldn't reach the mint. Check your connection and try again.",
            phase.message,
        )
        assertNoImplementationDetails(phase.message)
    }

    @Test
    fun mapsQuotedFfiFailureToWalletFacingCopy() {
        val phase = restoreMintFailurePhase(
            IllegalStateException(
                "FfiException(CALL_ERROR, errorMessage: \"Token Already Spent\")",
            ),
        )

        assertEquals("This token was already redeemed.", phase.message)
        assertNoImplementationDetails(phase.message)
    }

    @Test
    fun hidesUnknownCdkNamespaceBehindGenericFallback() {
        val phase = restoreMintFailurePhase(
            IllegalStateException(
                "FfiError.Internal(errorMessage=cdk_wallet::Error::Unknown(Custom(42)))",
            ),
        )

        assertEquals(
            "The wallet couldn't finish that action. Try again in a moment.",
            phase.message,
        )
        assertNoImplementationDetails(phase.message)
    }

    @Test
    fun hidesUnhelpfulThrowableWrapperBehindGenericFallback() {
        val phase = restoreMintFailurePhase(IllegalStateException())

        assertEquals(
            "The wallet couldn't finish that action. Try again in a moment.",
            phase.message,
        )
        assertNoImplementationDetails(phase.message)
    }

    @Test
    fun translatedFailureKeepsTheRetryRowState() {
        val phase: RestoreMintPhase = restoreMintFailurePhase(
            IllegalStateException("Network request timed out"),
        )

        // RestoreProgressRow renders its Retry action for every Failed phase.
        assertTrue(phase is RestoreMintPhase.Failed)
    }

    private fun assertNoImplementationDetails(message: String) {
        val lowered = message.lowercase()
        assertFalse(lowered.contains("ffi"))
        assertFalse(lowered.contains("cdk"))
        assertFalse(lowered.contains("exception"))
        assertFalse(lowered.contains("errormessage"))
        assertFalse(lowered.contains("code="))
        assertFalse(message.contains("::"))
    }
}
