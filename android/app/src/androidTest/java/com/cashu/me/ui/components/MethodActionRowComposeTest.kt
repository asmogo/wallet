package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MethodActionRowComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun enabledRowIsOneAccessibleActionAndInvokesCallback() {
        var clicks = 0
        compose.setCashuContent {
            MethodActionRow(
                icon = Icons.Outlined.QrCodeScanner,
                title = "Scan",
                subtitle = "Scan an ecash token",
                accessibilityLabel = "Scan QR code",
                onClick = { clicks += 1 },
            )
        }

        compose.onNodeWithContentDescription("Scan QR code")
            .assertIsDisplayed()
            .assertIsEnabled()
            .assertHasClickAction()
            .performClick()
        compose.runOnIdle { assertEquals(1, clicks) }
    }

    @Test
    fun unavailableRowStaysVisibleAndExplainsWhy() {
        compose.setCashuContent {
            Column {
                MethodActionRow(
                    icon = Icons.Outlined.CurrencyBitcoin,
                    title = "Bitcoin",
                    subtitle = "Lightning or on-chain",
                    accessibilityLabel = "Receive over Lightning or on-chain",
                    onClick = {},
                    enabled = false,
                    status = "Mint needed",
                )
            }
        }

        compose.onNodeWithContentDescription("Receive over Lightning or on-chain")
            .assertIsDisplayed()
            .assertIsNotEnabled()
        compose.onNodeWithText("Mint needed", useUnmergedTree = true)
            .assertIsDisplayed()
    }
}
