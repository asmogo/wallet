package com.cashu.me.ui.home

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
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
class HomeActionAccessibilityComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun homeActionsExposeOneLabelAndUnifiedFlowClickHints() {
        var receiveClicks = 0
        var sendClicks = 0

        compose.setCashuContent {
            ActionDuet(
                onReceive = { receiveClicks += 1 },
                onSend = { sendClicks += 1 },
                receiveEnabled = true,
                sendEnabled = true,
            )
        }

        assertActionSemantics(
            tag = UiTestTags.WalletReceive,
            label = "Receive",
            clickLabel = HomeActionAccessibility.ReceiveClickLabel,
        )
        assertActionSemantics(
            tag = UiTestTags.WalletSend,
            label = "Send",
            clickLabel = HomeActionAccessibility.SendClickLabel,
        )

        compose.onNodeWithTag(UiTestTags.WalletReceive).performClick()
        compose.onNodeWithTag(UiTestTags.WalletSend).performClick()

        compose.runOnIdle {
            assertEquals(1, receiveClicks)
            assertEquals(1, sendClicks)
        }
    }

    private fun assertActionSemantics(
        tag: String,
        label: String,
        clickLabel: String,
    ) {
        val node = compose.onNodeWithTag(tag)
            .assertIsDisplayed()
            .fetchSemanticsNode()

        assertEquals(
            listOf(label),
            node.config[SemanticsProperties.ContentDescription],
        )
        assertEquals(
            clickLabel,
            node.config[SemanticsActions.OnClick].label,
        )
        assertFalse(clickLabel.contains(label, ignoreCase = true))
        assertFalse(clickLabel.contains("option", ignoreCase = true))
        assertFalse(clickLabel.contains("chooser", ignoreCase = true))
    }
}
