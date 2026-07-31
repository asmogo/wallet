package com.cashu.me.ui.receive

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Models.TokenInfo
import com.cashu.me.ui.setCashuContent
import java.util.Locale
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReceiveActualFeeComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun receiptDisplaysSettledFeeInsteadOfPreview() {
        val review = TokenReview(
            token = "cashu-token",
            info = TokenInfo(
                amount = 100,
                mint = "https://mint.example.com",
                unit = "sat",
                memo = null,
                proofCount = 1,
            ),
            fee = 3,
            locked = false,
        )
        val claimed = settledTokenClaim(review, creditedAmount = 93)

        compose.setCashuContent {
            TokenClaimTerminal(
                status = claimed,
                formatter = AmountFormatter(Locale.US),
                useBitcoinSymbol = false,
                onDone = {},
                onRetry = {},
            )
        }

        compose.onNodeWithText("Amount").assertIsDisplayed()
        compose.onNodeWithText("93 sat").assertIsDisplayed()
        compose.onNodeWithText("Fee").assertIsDisplayed()
        compose.onNodeWithText("7 sat").assertIsDisplayed()
        compose.onNodeWithText("3 sat").assertDoesNotExist()
    }
}
