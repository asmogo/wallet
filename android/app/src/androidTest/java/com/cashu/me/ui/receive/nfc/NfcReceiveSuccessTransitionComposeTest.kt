package com.cashu.me.ui.receive.nfc

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.NfcReceive.NfcReceivePhase
import com.cashu.me.Core.NfcReceive.NfcReceiveState
import com.cashu.me.ui.setCashuContent
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NfcReceiveSuccessTransitionComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun processingMorphsDirectlyIntoTheSharedReceipt() {
        var state by mutableStateOf(NfcReceiveState(NfcReceivePhase.Redeeming))

        compose.setCashuContent {
            NfcReceiveOverlayContent(
                state = state,
                successAmountLabel = "19 sat",
                successMintName = "Minibits mint",
                onSuccessDone = {},
                onRetry = {},
            )
        }

        compose.onNodeWithText("Securing ecash").assertIsDisplayed()
        compose.runOnIdle {
            state = NfcReceiveState(
                phase = NfcReceivePhase.Success,
                amount = 19,
                settlementMint = "https://mint.example",
            )
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription("Success").assertIsDisplayed()
        compose.onNodeWithText("Payment Received!").assertIsDisplayed()
        compose.onNodeWithText("19 sat").assertIsDisplayed()
        compose.onNodeWithText("Minibits mint").assertIsDisplayed()
        compose.onNodeWithText("Done").assertIsDisplayed()
    }
}
