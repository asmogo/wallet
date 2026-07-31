package com.cashu.me.ui.receive

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
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
}
