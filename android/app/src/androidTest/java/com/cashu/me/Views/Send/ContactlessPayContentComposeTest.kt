package com.cashu.me.Views.Send

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ContactlessPayContentComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun disabledNfcExposesSettingsAction() {
        var settingsClicks = 0

        compose.setCashuContent {
            Box(Modifier.width(360.dp)) {
                ContactlessPayContent(
                    availability = ContactlessAvailability.Disabled,
                    status = "",
                    error = null,
                    isProcessing = false,
                    paymentComplete = false,
                    lastPaymentAmount = null,
                    onOpenNfcSettings = { settingsClicks += 1 },
                    onDone = {},
                )
            }
        }

        compose.onNodeWithText("NFC is disabled in system settings.").assertIsDisplayed()
        compose.onNodeWithText("Open NFC settings").performClick()
        compose.runOnIdle {
            assertEquals(1, settingsClicks)
        }
    }

    @Test
    fun processingStateRendersAtLargeFontWithoutRedundantActions() {
        compose.setCashuContent(fontScale = 2f) {
            Box(
                Modifier
                    .width(280.dp)
                    .testTag("contactlessLargeFont"),
            ) {
                ContactlessPayContent(
                    availability = ContactlessAvailability.Ready,
                    status = "Writing payment...",
                    error = null,
                    isProcessing = true,
                    paymentComplete = false,
                    lastPaymentAmount = null,
                    onOpenNfcSettings = {},
                    onDone = {},
                )
            }
        }

        compose.onNodeWithText("Contactless").assertIsDisplayed()
        compose.onNodeWithText("Writing payment...").assertIsDisplayed()
        compose.onNodeWithText("Close").assertDoesNotExist()
        compose.onNodeWithText("Reset").assertDoesNotExist()
        compose.onNodeWithTag("contactlessLargeFont").captureToImage().assertNonEmpty()
    }

    @Test
    fun successUsesSharedTerminalAndExposesDone() {
        var doneClicks = 0

        compose.setCashuContent {
            Box(Modifier.width(360.dp)) {
                ContactlessPayContent(
                    availability = ContactlessAvailability.Ready,
                    status = "Payment sent.",
                    error = null,
                    isProcessing = false,
                    paymentComplete = true,
                    lastPaymentAmount = 42,
                    onOpenNfcSettings = {},
                    onDone = { doneClicks += 1 },
                )
            }
        }

        compose.onNodeWithText("Payment sent").assertIsDisplayed()
        compose.onNodeWithText("₿42").assertIsDisplayed()
        compose.onNodeWithText("Done").performClick()
        compose.runOnIdle { assertEquals(1, doneClicks) }
    }

    private fun ImageBitmap.assertNonEmpty() {
        assertTrue(width > 0)
        assertTrue(height > 0)
    }
}
