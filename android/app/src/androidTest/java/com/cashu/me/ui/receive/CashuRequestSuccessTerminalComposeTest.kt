package com.cashu.me.ui.receive

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CashuRequestSuccessTerminalComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun receiptUsesSharedTerminalAndWaitsForDone() {
        var done = false

        compose.setCashuContent {
            CashuRequestSuccessTerminal(
                amountLabel = "19 sat",
                mintName = "Minibits mint",
                onDone = { done = true },
            )
        }

        compose.onNodeWithContentDescription("Success").assertIsDisplayed()
        compose.onNodeWithText("Payment Received!").assertIsDisplayed()
        compose.onNodeWithText("Amount").assertIsDisplayed()
        compose.onNodeWithText("19 sat").assertIsDisplayed()
        compose.onNodeWithText("Mint").assertIsDisplayed()
        compose.onNodeWithText("Minibits mint").assertIsDisplayed()

        compose.runOnIdle { assertTrue(!done) }
        compose.onNodeWithText("Done").performClick()
        compose.runOnIdle { assertTrue(done) }
    }
}
