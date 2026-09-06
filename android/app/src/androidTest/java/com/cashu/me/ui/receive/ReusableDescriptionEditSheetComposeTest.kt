package com.cashu.me.ui.receive

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReusableDescriptionEditSheetComposeTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun savesTrimmedMultilineDescriptionWithKeyboardOpen() {
        var saved: String? = null
        compose.setCashuContent {
            ReusableDescriptionEditSheet("Coffee tips", onDone = { saved = it }, onDismiss = {})
        }
        compose.onNodeWithTag("reusable-description-field")
            .performTextReplacement("  Coffee tips\nThank you  ")
        compose.onNodeWithTag("reusable-description-save").performScrollTo().assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals("Coffee tips\nThank you", saved) }
    }

    @Test
    fun clearingDescriptionSavesNil() {
        var saved: String? = "old"
        compose.setCashuContent {
            ReusableDescriptionEditSheet("Coffee tips", onDone = { saved = it }, onDismiss = {})
        }
        compose.onNodeWithTag("reusable-description-field").performTextReplacement("   ")
        compose.onNodeWithTag("reusable-description-save").performScrollTo().performClick()
        compose.runOnIdle { assertNull(saved) }
    }

    @Test
    fun capsLongDraftAndCanCloseWithoutSavingAtLargeFont() {
        var saved = false
        var dismissed = false
        compose.setCashuContent(darkTheme = true, fontScale = 1.6f) {
            ReusableDescriptionEditSheet(null, onDone = { saved = true }, onDismiss = { dismissed = true })
        }
        compose.onNodeWithTag("reusable-description-field").performTextReplacement("x".repeat(700))
        compose.onNodeWithText("640 / 640").performScrollTo().assertIsDisplayed()
        compose.onNodeWithContentDescription("Close").performScrollTo().performClick()
        compose.runOnIdle {
            assertTrue(dismissed)
            assertFalse(saved)
        }
    }
}
