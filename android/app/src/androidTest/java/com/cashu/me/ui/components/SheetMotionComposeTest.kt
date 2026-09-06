package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SheetState
import androidx.compose.material3.SheetValue
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import com.cashu.me.ui.shell.WalletFlow
import com.cashu.me.ui.shell.WalletFlowSheetHost
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@OptIn(ExperimentalMaterial3Api::class)
@RunWith(AndroidJUnit4::class)
class SheetMotionComposeTest {
    private val durationScale = object : MotionDurationScale {
        override var scaleFactor = 1f
    }
    // Exercise real interpolation even when the test device disables animations.
    @get:Rule val compose = createComposeRule(effectContext = durationScale)

    @Test
    fun unitSelectionWaitsForDismissalAndRepeatedTapsSelectOnlyOnce() {
        val selected = mutableListOf<String>()
        compose.setCashuContent {
            UnitPickerSheet(
                units = listOf("sat", "usd"),
                selectedUnit = "sat",
                onSelect = { selected += it },
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false

        compose.onNodeWithText("USD").performClick()
        compose.onNodeWithText("SAT").performClick()
        compose.mainClock.advanceTimeBy(32)
        compose.runOnIdle { assertTrue(selected.isEmpty()) }

        compose.mainClock.advanceTimeBy(2_000)
        compose.runOnIdle { assertEquals(listOf("usd"), selected) }
    }

    @Test
    fun anyMintSelectionAlsoWaitsForDismissal() {
        var selections = 0
        compose.setCashuContent {
            MintPickerSheet(
                mints = emptyList(),
                activeMintUrl = null,
                allowAnyMint = true,
                onSelect = { assertEquals(null, it); selections++ },
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false

        compose.onNodeWithText("Any mint").performClick()
        compose.mainClock.advanceTimeBy(32)
        compose.runOnIdle { assertEquals(0, selections) }
        compose.mainClock.advanceTimeBy(2_000)
        compose.runOnIdle { assertEquals(1, selections) }
    }

    @Test
    fun disabledAnimationsStillDeliverTheSelection() {
        durationScale.scaleFactor = 0f
        val selected = mutableListOf<String>()
        compose.setCashuContent {
            UnitPickerSheet(
                units = listOf("sat", "usd"),
                selectedUnit = "sat",
                onSelect = { selected += it },
                onDismiss = {},
            )
        }
        compose.onNodeWithText("USD").performClick()
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(listOf("usd"), selected) }
    }

    @Test
    fun interruptedDismissalRestoresBackdropAndDoesNotDispatchTheAction() {
        lateinit var sheetState: SheetState
        lateinit var scope: CoroutineScope
        lateinit var dismiss: SheetDismissAction
        val events = mutableListOf<String>()
        compose.setCashuContent {
            sheetState = rememberBottomSheetState(
                initialValue = SheetValue.Hidden,
                enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
            )
            scope = rememberCoroutineScope()
            dismiss = rememberSheetDismissAction(sheetState)
            CashuModalBottomSheet(
                sheetState = sheetState,
                onDismissRequest = {},
                onBackdropVisibilityChanged = { events += "backdrop:$it" },
            ) { Box(Modifier.height(400.dp)) { Text("Receipt") } }
        }
        compose.waitForIdle()
        compose.mainClock.autoAdvance = false
        var startingOffset = 0f
        compose.runOnIdle {
            assertTrue(sheetState.isVisible)
            startingOffset = sheetState.requireOffset()
            events.clear()
            dismiss { events += "action" }
        }
        compose.mainClock.advanceTimeBy(64)
        compose.runOnIdle {
            assertEquals(listOf("backdrop:false"), events)
            assertTrue(sheetState.isVisible)
            assertTrue(sheetState.requireOffset() > startingOffset)
            scope.launch { sheetState.show() }
        }
        compose.mainClock.advanceTimeBy(2_000)
        compose.runOnIdle {
            assertTrue(sheetState.isVisible)
            assertEquals(listOf("backdrop:false", "backdrop:true"), events)
            dismiss { events += "action" }
        }
        compose.mainClock.advanceTimeBy(2_000)
        compose.runOnIdle {
            assertFalse(sheetState.isVisible)
            assertEquals(listOf("backdrop:false", "backdrop:true", "backdrop:false", "action"), events)
        }
    }

    @Test
    fun lockedPaymentSheetRejectsProgrammaticDismissal() {
        var dismissals = 0
        compose.setCashuContent {
            WalletFlowSheetHost(
                flow = WalletFlow.Send,
                dismissLocked = true,
                onBackdropVisibilityChanged = {},
                onDismissed = { dismissals++ },
                snackbarHostState = remember { SnackbarHostState() },
            ) { _, close ->
                PrimaryButton(text = "Close payment", onClick = close)
            }
        }
        compose.onNodeWithText("Close payment").performClick()
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(0, dismissals) }
        compose.onNodeWithText("Close payment").assertExists()
    }
}
