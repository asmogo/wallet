package com.cashu.me.ui.receive

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Models.TokenInfo
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReceiveP2PKLockReviewComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun heldKeyShowsRecipientAndClaimableStatus() {
        val state = p2pkLockState(P2PK_TOKEN) { targets ->
            targets == listOf(P2PK_TARGET)
        }
        val locked = state as P2PKLockState.Locked
        assertEquals(listOf(P2PK_TARGET), locked.targets)
        assertTrue(locked.claimable)
        setLockContent(locked)

        compose.onNodeWithText("Locked to").assertIsDisplayed()
        compose.onNodeWithText(P2PK_TARGET_LABEL).assertIsDisplayed()
        compose.onNodeWithText("Status").assertIsDisplayed()
        compose.onNodeWithText("Claimable · Your key").assertIsDisplayed()
    }

    @Test
    fun unheldKeyShowsSameRecipientAndUnclaimableStatus() {
        val state = p2pkLockState(P2PK_TOKEN) { false }
        val locked = state as P2PKLockState.Locked
        assertEquals(listOf(P2PK_TARGET), locked.targets)
        assertFalse(locked.claimable)
        setLockContent(locked)

        compose.onNodeWithText("Locked to").assertIsDisplayed()
        compose.onNodeWithText(P2PK_TARGET_LABEL).assertIsDisplayed()
        compose.onNodeWithText("Status").assertIsDisplayed()
        compose.onNodeWithText("Unclaimable · Key unavailable").assertIsDisplayed()
    }

    private fun setLockContent(lock: P2PKLockState.Locked) {
        compose.setCashuContent {
            TokenInspectorRows(
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
        }
    }

    private companion object {
        const val P2PK_TARGET =
            "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        const val P2PK_TARGET_LABEL = "0279be667ef9…815b16f81798"

        // Cashu V3 fixture with one proof whose secret is locked to P2PK_TARGET.
        const val P2PK_TOKEN =
            "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vbWludC5leGFtcGxlIiwicHJvb2ZzIjpbeyJpZCI6IjAwYmZhNzMzMDJkMTJmZmQiLCJhbW91bnQiOjEsInNlY3JldCI6IltcIlAyUEtcIix7XCJub25jZVwiOlwiMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMFwiLFwiZGF0YVwiOlwiMDI3OWJlNjY3ZWY5ZGNiYmFjNTVhMDYyOTVjZTg3MGIwNzAyOWJmY2RiMmRjZTI4ZDk1OWYyODE1YjE2ZjgxNzk4XCJ9XSIsIkMiOiIwMjc5YmU2NjdlZjlkY2JiYWM1NWEwNjI5NWNlODcwYjA3MDI5YmZjZGIyZGNlMjhkOTU5ZjI4MTViMTZmODE3OTgifV19XX0="
    }
}
