package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LargeFontControlsComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun settingsRowsRenderAtLargeFontAndCompactWidth() {
        compose.setCashuContent(fontScale = 2f) {
            Column(Modifier.width(280.dp).testTag("settingsRows")) {
                ToggleRow(
                    title = "Privacy mode",
                    subtitle = "Hide balances until tapped",
                    checked = true,
                    onCheckedChange = {},
                    leadingIcon = Icons.Outlined.PrivacyTip,
                )
                NavRow(
                    title = "Backup & Restore",
                    subtitle = "Seed phrase and restore tools",
                    onClick = {},
                )
            }
        }

        compose.onNodeWithText("Privacy mode").assertIsDisplayed()
        compose.onNodeWithText("Hide balances until tapped").assertIsDisplayed()
        compose.onNodeWithText("Backup & Restore").assertIsDisplayed()
        compose.onNodeWithTag("settingsRows").captureToImage().assertNonEmpty()
    }

    @Test
    fun numberPadRendersAtLargeFontAndCompactWidth() {
        compose.setCashuContent(fontScale = 2f) {
            Column(Modifier.width(240.dp).testTag("numberPadLargeFont")) {
                NumberPad(amount = "123", onAmountChange = {})
            }
        }

        compose.onNodeWithText("1").assertIsDisplayed()
        compose.onNodeWithText("9").assertIsDisplayed()
        compose.onNodeWithTag("numberPadLargeFont").captureToImage().assertNonEmpty()
    }

    private fun ImageBitmap.assertNonEmpty() {
        assertTrue(width > 0)
        assertTrue(height > 0)
    }
}
