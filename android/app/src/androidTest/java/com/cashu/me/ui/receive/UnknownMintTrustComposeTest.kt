package com.cashu.me.ui.receive

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class UnknownMintTrustComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun warningShowsNormalizedHostAndExplainsMintAddition() {
        val trust = ReceiveMintTrust(
            host = "mint.example.com",
            mintKnown = false,
        )

        compose.setCashuContent {
            UnknownMintTrustNotice(trust)
        }

        compose.onNodeWithText("New mint: mint.example.com").assertIsDisplayed()
        compose.onNodeWithText(
            "Receiving this token will add the mint to your wallet. Continue only if you trust it.",
        ).assertIsDisplayed()
    }

    @Test
    fun dialogRequiresExplicitTrustAction() {
        var confirmations = 0
        val trust = ReceiveMintTrust(
            host = "mint.example.com",
            mintKnown = false,
        )

        compose.setCashuContent {
            Column {
                UnknownMintTrustConfirmationDialog(
                    trust = trust,
                    onConfirm = { confirmations += 1 },
                    onDismiss = {},
                )
            }
        }

        compose.onNodeWithText("Trust this mint?").assertIsDisplayed()
        compose.onNodeWithText("mint.example.com").assertIsDisplayed()
        compose.onNodeWithText(
            "Receiving this token will add the mint to your wallet. Only continue if you trust it.",
        ).assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, confirmations) }

        compose.onNodeWithText("Trust & receive").performClick()
        compose.runOnIdle { assertEquals(1, confirmations) }
    }
}
