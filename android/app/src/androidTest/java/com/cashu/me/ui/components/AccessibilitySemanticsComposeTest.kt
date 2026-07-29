package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountDisplayText
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccessibilitySemanticsComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun criticalWalletControlsExposeTalkBackLabelsAndActions() {
        var rowClicks = 0
        var privacyEnabled = true

        compose.setCashuContent {
            Column(
                Modifier
                    .width(360.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                BalanceDisplay(
                    amount = AmountDisplayText(
                        primary = "42 sat",
                        secondary = "\$0.01",
                        effectivePrimary = AmountDisplayPrimary.Sats,
                    ),
                    modifier = Modifier.testTag("balanceDisplay"),
                )
                QrCard(
                    content = "cashuA-test-token",
                    modifier = Modifier.testTag("qrCard"),
                    staticOnly = true,
                )
                NumberPad(
                    amount = "123",
                    onAmountChange = {},
                    modifier = Modifier.testTag("numberPad"),
                )
                TransactionRow(
                    model = TransactionRowModel(
                        transaction = WalletTransaction(
                            id = "tx-accessibility",
                            amount = 21,
                            type = TransactionType.Incoming,
                            kind = TransactionKind.Ecash,
                            dateEpochMillis = 0L,
                            status = TransactionStatus.Completed,
                        ),
                        title = "Received ecash",
                        timestamp = "Today",
                        primaryAmount = "21 sat",
                        secondaryAmount = "\$0.01",
                    ),
                    onClick = { rowClicks += 1 },
                    modifier = Modifier.testTag("transactionRow"),
                )
                ToggleRow(
                    title = "Privacy mode",
                    subtitle = "Hide balances until tapped",
                    checked = privacyEnabled,
                    onCheckedChange = { privacyEnabled = it },
                    modifier = Modifier.testTag("privacyToggle"),
                )
            }
        }

        compose.onNodeWithTag("balanceDisplay")
            .assertIsDisplayed()
            .assertHasNoClickAction()
        compose.onNodeWithContentDescription("Balance: 42 sat")
            .assertIsDisplayed()
        compose.onNodeWithContentDescription("QR code. Long press for copy and share options.")
            .performScrollTo()
            .assertIsDisplayed()
            .assertHasClickAction()
            .performTouchInput { longClick() }
        compose.onNodeWithText("Copy").assertIsDisplayed()
        compose.onNodeWithText("Share").assertIsDisplayed()
        compose.onNodeWithText("Copy").performClick()
        compose.onNodeWithContentDescription("Delete. Long press to clear.")
            .performScrollTo()
            .assertIsDisplayed()
            .assertHasClickAction()
        compose.onNodeWithContentDescription("Received ecash, Incoming, Completed, +21 sat, \$0.01, Today")
            .performScrollTo()
            .assertHasClickAction()
            .performClick()
        compose.onNodeWithTag("privacyToggle")
            .performScrollTo()
            .assertHasClickAction()
            .performClick()

        compose.runOnIdle {
            assertEquals(1, rowClicks)
            assertFalse(privacyEnabled)
        }
    }

    @Test
    fun balanceAccessibilityNamesThePreferredPrimaryAmount() {
        compose.setCashuContent {
            BalanceDisplay(
                amount = AmountDisplayText(
                    primary = "\$20.00",
                    secondary = "100,000 sat",
                    effectivePrimary = AmountDisplayPrimary.Fiat,
                ),
            )
        }

        compose.onNodeWithContentDescription("Balance: \$20.00")
            .assertIsDisplayed()
        compose.onNodeWithText("100,000 sat")
            .assertIsDisplayed()
    }
}
