package com.cashu.me.ui.components

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ActionConfirmationSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun cancelDoesNotRunTheDestructiveAction() {
        var actions = 0
        var dismissals = 0
        compose.setCashuContent {
            ActionConfirmationSheet(
                title = "Remove mint?",
                message = "Unspent ecash will need to be restored from your seed phrase.",
                actionLabel = "Remove",
                destructive = true,
                onConfirm = { actions++ },
                onDismiss = { dismissals++ },
            )
        }
        compose.onNodeWithText("Cancel").performClick()
        compose.runOnIdle {
            assertEquals(0, actions)
            assertEquals(1, dismissals)
        }
    }

    @Test
    fun repeatedConfirmationOnlySubmitsOnce() {
        var actions = 0
        compose.setCashuContent {
            ActionConfirmationSheet(
                title = "Remove mint?",
                message = "Unspent ecash will need to be restored from your seed phrase.",
                actionLabel = "Remove",
                destructive = true,
                onConfirm = { actions++ },
                onDismiss = {},
            )
        }
        compose.onNodeWithText("Remove").performClick().performClick()
        compose.runOnIdle { assertEquals(1, actions) }
    }

    @Test
    fun largeTextKeepsWarningAndBothActionsReachable() {
        compose.setCashuContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
                ActionConfirmationSheet(
                    title = "Remove unclaimed ecash?",
                    message = "This ecash has not been claimed. Removing it discards the token. You will need the token again to claim it.",
                    actionLabel = "Remove",
                    destructive = true,
                    onConfirm = {},
                    onDismiss = {},
                )
            }
        }
        compose.onNodeWithText("Remove").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Cancel").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Remove unclaimed ecash?").performScrollTo().assertIsDisplayed()
    }
}
