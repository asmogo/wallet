package com.cashu.me.ui.receive

import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GeneratedInvoiceAmountComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun bolt11SatsPrimaryLeadsAndExposesFiatAlternativeAccessibly() {
        compose.setCashuContent {
            GeneratedInvoiceAmount(
                amount = 100_000_000,
                amountLabel = "100,000,000 sat",
                unit = "sat",
                paymentMethod = PaymentMethodKind.Bolt11,
                primary = AmountDisplayPrimary.Sats,
                onFlipPrimary = {},
                btcPrice = 20_000.0,
                currencyCode = "USD",
                useBitcoinSymbol = false,
            )
        }

        assertPrimaryAboveAlternate(
            primary = "100,000,000 sat",
            alternate = "$20,000.00",
        )
        compose.onNodeWithContentDescription(
            "Alternate amount: $20,000.00. Tap to make it primary.",
        )
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    @Test
    fun fixedBolt12FiatPrimaryLeadsAndExposesSatsAlternativeAccessibly() {
        compose.setCashuContent {
            GeneratedInvoiceAmount(
                amount = 100_000_000,
                amountLabel = "100,000,000 sat",
                unit = "sat",
                paymentMethod = PaymentMethodKind.Bolt12,
                primary = AmountDisplayPrimary.Fiat,
                onFlipPrimary = {},
                btcPrice = 20_000.0,
                currencyCode = "USD",
                useBitcoinSymbol = false,
            )
        }

        assertPrimaryAboveAlternate(
            primary = "$20,000.00",
            alternate = "100,000,000 sat",
        )
        compose.onNodeWithContentDescription(
            "Alternate amount: 100,000,000 sat. Tap to make it primary.",
        )
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    private fun assertPrimaryAboveAlternate(primary: String, alternate: String) {
        val primaryNode = compose.onNodeWithText(primary).assertIsDisplayed().fetchSemanticsNode()
        val alternateNode = compose.onNodeWithText(alternate).assertIsDisplayed().fetchSemanticsNode()

        assertTrue(
            "Expected preferred amount '$primary' above alternate '$alternate'",
            primaryNode.boundsInRoot.top < alternateNode.boundsInRoot.top,
        )
    }
}
