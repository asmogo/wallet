package com.cashu.me.ui.send

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import com.cashu.me.ui.settings.P2PKKeyDisplay
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class P2pkRecipientParityComposeTest {
    @get:Rule
    val compose = createComposeRule()

    private val recipient = "02${"a".repeat(64)}"

    @Test
    fun confirmedRecipientIsCompactAndActionsAreAccessible() {
        var changeClicks = 0
        var removeClicks = 0
        compose.setCashuContent {
            P2pkRecipientConfirmation(
                confirmedPubkey = recipient,
                recipientIsPrimaryKey = true,
                onEditRecipient = { changeClicks += 1 },
                onRemoveRecipient = { removeClicks += 1 },
            )
        }

        compose.onNodeWithText("LOCKED TO").assertIsDisplayed()
        compose.onNodeWithText("Your key").assertIsDisplayed()
        compose.onNodeWithContentDescription("Locked to public key")
            .performClick()
        compose.onNodeWithContentDescription("Remove lock")
            .performClick()

        compose.runOnIdle {
            assertEquals(1, changeClicks)
            assertEquals(1, removeClicks)
        }
    }

    @Test
    fun externalRecipientUsesTruncatedPublicKeyIdentity() {
        val label = P2PKKeyDisplay.shortLabel(recipient)
        compose.setCashuContent {
            P2pkRecipientConfirmation(
                confirmedPubkey = recipient,
                recipientIsPrimaryKey = false,
                onEditRecipient = {},
                onRemoveRecipient = {},
            )
        }

        compose.onNodeWithText(label).assertIsDisplayed()
        compose.onNodeWithContentDescription("Locked to public key").assertIsDisplayed()
    }

    @Test
    fun lockToolbarMatchesIosLabelAndActionHint() {
        var clicks = 0
        compose.setCashuContent {
            LockEcashToolbarAction(
                onClick = { clicks += 1 },
            )
        }

        assertLockSemantics()
        compose.onNodeWithTag(UiTestTags.LockEcashToggle).performClick()
        compose.runOnIdle {
            assertEquals(1, clicks)
        }
    }

    private fun assertLockSemantics() {
        val semantics = compose.onNodeWithTag(UiTestTags.LockEcashToggle)
            .assertIsDisplayed()
            .fetchSemanticsNode()
            .config

        assertEquals(listOf(LockEcashCopy.Label), semantics[SemanticsProperties.ContentDescription])
        assertEquals(LockEcashCopy.Hint, semantics[SemanticsActions.OnClick].label)
        assertFalse(semantics.contains(SemanticsProperties.StateDescription))
    }
}
