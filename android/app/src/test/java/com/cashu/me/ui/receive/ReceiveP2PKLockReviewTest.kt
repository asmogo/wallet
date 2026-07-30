package com.cashu.me.ui.receive

import com.cashu.me.Models.TokenInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiveP2PKLockReviewTest {
    @Test
    fun heldTargetRemainsIdentifiedAndEnablesClaim() {
        val state = p2pkLockStateForTargets(listOf(P2PK_TARGET)) { targets ->
            targets == listOf(P2PK_TARGET)
        }

        val locked = state as P2PKLockState.Locked
        val presentation = requireNotNull(locked.presentation())
        assertEquals(listOf(P2PK_TARGET), locked.targets)
        assertTrue(locked.claimable)
        assertEquals(listOf(P2PK_TARGET_LABEL), presentation.targetLabels)
        assertEquals("Claimable · Your key", presentation.statusText)
        assertTrue(reviewWith(locked).canClaim)
    }

    @Test
    fun unheldTargetRemainsIdentifiedAndDisablesClaim() {
        val state = p2pkLockStateForTargets(listOf(P2PK_TARGET)) { false }

        val locked = state as P2PKLockState.Locked
        val presentation = requireNotNull(locked.presentation())
        assertEquals(listOf(P2PK_TARGET), locked.targets)
        assertFalse(locked.claimable)
        assertEquals(listOf(P2PK_TARGET_LABEL), presentation.targetLabels)
        assertEquals("Unclaimable · Key unavailable", presentation.statusText)
        assertFalse(reviewWith(locked).canClaim)
    }

    private fun reviewWith(lock: P2PKLockState): TokenReview = TokenReview(
        token = "cashuBfixture",
        info = TokenInfo(
            amount = 1,
            mint = "https://mint.example",
            unit = "sat",
            memo = null,
            proofCount = 1,
        ),
        fee = 0,
        p2pkLock = lock,
    )

    private companion object {
        const val P2PK_TARGET =
            "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        const val P2PK_TARGET_LABEL = "0279be667ef9…815b16f81798"
    }
}
