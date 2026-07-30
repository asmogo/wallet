package com.cashu.me.ui.send

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LockEcashAccessibilityComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun lockControlAnnouncesPlainLanguageOutcomeForBothStates() {
        compose.setCashuContent {
            var locked by remember { mutableStateOf(false) }
            LockEcashToolbarAction(
                locked = locked,
                onToggle = { locked = !locked },
            )
        }

        assertLockSemantics(
            state = "Off. Anyone with the ecash token can claim it.",
        )

        compose.onNodeWithTag(UiTestTags.LockEcashToggle).performClick()

        assertLockSemantics(
            state = "On. Only the recipient with the selected key can claim it.",
        )
    }

    @Test
    fun expandedLockSectionLeadsWithOutcomeAndKeepsProtocolNameSupporting() {
        compose.setCashuContent {
            P2pkLockSection(
                input = "",
                onInputChange = {},
                inputError = null,
                myKeyHex = "02${"a".repeat(64)}",
                onUseMyKey = {},
            )
        }

        compose.onNodeWithText(LockEcashCopy.Label).assertIsDisplayed()
        compose.onNodeWithText(LockEcashCopy.RecipientEffect).assertIsDisplayed()
        compose.onNodeWithText(LockEcashCopy.RecipientKeyLabel).assertIsDisplayed()
        compose.onNodeWithText("Lock ecash to my key").assertIsDisplayed()
    }

    private fun assertLockSemantics(state: String) {
        val semantics = compose.onNodeWithTag(UiTestTags.LockEcashToggle)
            .assertIsDisplayed()
            .fetchSemanticsNode()
            .config

        assertEquals(
            listOf(LockEcashCopy.Label),
            semantics[SemanticsProperties.ContentDescription],
        )
        assertEquals(state, semantics[SemanticsProperties.StateDescription])
        assertFalse(
            semantics[SemanticsProperties.ContentDescription]
                .any { it.contains("P2PK", ignoreCase = true) },
        )
        assertFalse(state.contains("P2PK", ignoreCase = true))
    }
}
