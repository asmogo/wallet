package com.cashu.me.ui.send

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.ui.components.PaymentStatusPhase
import com.cashu.me.ui.components.PaymentStatusScreen
import com.cashu.me.ui.setCashuContent
import java.util.Locale
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SendPaymentStatusDetailsComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun paymentFactsStayVisibleAcrossProcessingSuccessAndFailure() {
        var phase by mutableStateOf(PaymentStatusPhase.Processing)
        val details = SendPaymentDetails(
            listOf(
                SendPaymentDetailRow(
                    SendPaymentDetailKey.Method,
                    "Method",
                    SendPaymentDetailValue.Text("BOLT11"),
                ),
                SendPaymentDetailRow(
                    SendPaymentDetailKey.Amount,
                    "Amount",
                    SendPaymentDetailValue.Sats(21),
                    valueMonospaced = true,
                ),
                SendPaymentDetailRow(
                    SendPaymentDetailKey.NetworkFee,
                    "Network fee",
                    SendPaymentDetailValue.Sats(3, isUpperBound = true),
                    valueMonospaced = true,
                ),
            ),
        )

        compose.setCashuContent {
            PaymentStatusScreen(
                phase = phase,
                title = when (phase) {
                    PaymentStatusPhase.Processing -> "Sending payment…"
                    PaymentStatusPhase.Success -> "Payment sent"
                    PaymentStatusPhase.Failure -> "Payment failed"
                },
                rows = {
                    SendPaymentDetailRows(
                        details = details,
                        formatter = AmountFormatter(Locale.US),
                        useBitcoinSymbol = false,
                    )
                },
                showRowsDuringProcessing = true,
            )
        }

        assertFactsDisplayed()
        compose.runOnIdle { phase = PaymentStatusPhase.Success }
        assertFactsDisplayed()
        compose.runOnIdle { phase = PaymentStatusPhase.Failure }
        assertFactsDisplayed()
    }

    private fun assertFactsDisplayed() {
        compose.onNodeWithText("Method").assertIsDisplayed()
        compose.onNodeWithText("BOLT11").assertIsDisplayed()
        compose.onNodeWithText("Amount").assertIsDisplayed()
        compose.onNodeWithText("21 sat").assertIsDisplayed()
        compose.onNodeWithText("Network fee").assertIsDisplayed()
        compose.onNodeWithText("Up to 3 sat").assertIsDisplayed()
    }
}
