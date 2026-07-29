package com.cashu.me.ui.home

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.click
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountDisplayText
import com.cashu.me.ui.components.BalanceDisplay
import com.cashu.me.ui.setCashuContent
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HomeRuntimeReadinessComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun preparationStateIsVisibleAndPaymentActionsCannotBeInvoked() {
        var receiveClicks = 0
        var sendClicks = 0

        compose.setCashuContent {
            Column {
                BalanceDisplay(
                    amount = AmountDisplayText(
                        primary = "42 sat",
                        secondary = "\$0.01",
                        effectivePrimary = AmountDisplayPrimary.Sats,
                    ),
                    statusMessage = PREPARING_WALLET_LABEL,
                )
                ActionDuet(
                    onReceive = { receiveClicks += 1 },
                    onSend = { sendClicks += 1 },
                    receiveEnabled = false,
                    sendEnabled = false,
                )
            }
        }

        compose.onNodeWithText(PREPARING_WALLET_LABEL).assertIsDisplayed()
        compose.onNodeWithTag(UiTestTags.WalletReceive)
            .assertIsNotEnabled()
            .performTouchInput { click() }
        compose.onNodeWithTag(UiTestTags.WalletSend)
            .assertIsNotEnabled()
            .performTouchInput { click() }
        compose.runOnIdle {
            assertEquals(0, receiveClicks)
            assertEquals(0, sendClicks)
        }
    }
}
