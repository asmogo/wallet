package com.cashu.me.ui.send

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import com.cashu.me.ui.settings.P2PKKeyDisplay
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class P2pkRecipientConfirmationComposeTest {
    @get:Rule
    val compose = createComposeRule()

    private val recipient = "02${"a".repeat(64)}"

    @Test
    fun ownRecipientConfirmationIsCompactAndActionsAreAccessible() {
        var editClicks = 0
        var removeClicks = 0
        compose.setCashuContent {
            P2pkLockSection(
                input = recipient,
                onInputChange = {},
                inputError = null,
                confirmedPubkey = recipient,
                recipientIsOwnKey = true,
                onEditRecipient = { editClicks += 1 },
                onRemoveRecipient = { removeClicks += 1 },
                myKeyHex = recipient,
                onUseMyKey = {},
            )
        }

        compose.onNodeWithText("Locked to").assertIsDisplayed()
        compose.onNodeWithText("Your key").assertIsDisplayed()
        compose.onNodeWithText("Recipient P2PK pubkey").assertDoesNotExist()
        compose.onNodeWithContentDescription("Locked ecash recipient: Your key")
            .assertIsDisplayed()
        compose.onNodeWithContentDescription("Edit locked ecash recipient")
            .assertIsDisplayed()
            .performClick()
        compose.onNodeWithContentDescription("Remove locked ecash recipient")
            .assertIsDisplayed()
            .performClick()

        compose.runOnIdle {
            assertEquals(1, editClicks)
            assertEquals(1, removeClicks)
        }
    }

    @Test
    fun externalRecipientUsesTruncatedPublicKeyIdentity() {
        val label = P2PKKeyDisplay.shortLabel(recipient)
        compose.setCashuContent {
            P2pkLockSection(
                input = recipient,
                onInputChange = {},
                inputError = null,
                confirmedPubkey = recipient,
                recipientIsOwnKey = false,
                onEditRecipient = {},
                onRemoveRecipient = {},
                myKeyHex = null,
                onUseMyKey = {},
            )
        }

        compose.onNodeWithText(label).assertIsDisplayed()
        compose.onNodeWithContentDescription("Locked ecash recipient: $label")
            .assertIsDisplayed()
    }
}
