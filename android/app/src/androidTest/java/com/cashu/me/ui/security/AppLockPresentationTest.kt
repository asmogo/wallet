package com.cashu.me.ui.security

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalMaterial3Api::class)
class AppLockPresentationTest {
    @get:Rule val compose = createComposeRule()
    private val device get() = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun lockBlocksTouchBackAndAccessibilityAboveExistingAndNewSheets() {
        var locked by mutableStateOf(false)
        var nested by mutableStateOf(false)
        var draft by mutableStateOf("Sensitive payment draft")
        var paid = 0
        var dismissed = 0
        var attempts = 0
        compose.setCashuContent {
            Column { Text("Wallet balance"); Text(draft) }
            ModalBottomSheet(onDismissRequest = { dismissed++ }) {
                Text(draft)
                Button(onClick = { paid++ }) { Text("Pay underlying") }
            }
            if (nested) {
                ModalBottomSheet(onDismissRequest = { dismissed++ }) { Text("Sensitive nested settings") }
            }
            if (locked) {
                AppLockDialog {
                    AppLockGateContent(isAuthenticating = false, onUnlock = {
                        attempts++
                        // First attempt models cancelled authentication.
                        if (attempts > 1) locked = false
                    })
                }
            }
        }
        compose.waitForIdle()
        compose.runOnIdle { locked = true }
        compose.waitForIdle()
        assertTrue(device.wait(Until.hasObject(By.text("Wallet Locked")), 5_000))
        assertFalse(device.hasObject(By.text("Sensitive payment draft")))
        device.pressBack()
        device.click(device.displayWidth / 2, device.displayHeight / 2)
        compose.runOnIdle { assertEquals(0, paid); assertEquals(0, dismissed) }
        // An asynchronous flow may open another native sheet after locking.
        compose.runOnIdle { nested = true }
        compose.waitForIdle()
        assertTrue(device.wait(Until.hasObject(By.text("Wallet Locked")), 5_000))
        assertFalse(device.hasObject(By.text("Sensitive nested settings")))
        device.findObject(By.text("Unlock")).click()
        compose.waitForIdle()
        assertTrue(device.wait(Until.hasObject(By.text("Wallet Locked")), 5_000))
        compose.runOnIdle { draft = "Payment complete" }
        compose.waitForIdle()
        device.findObject(By.text("Unlock")).click()
        compose.waitForIdle()
        assertTrue(device.wait(Until.hasObject(By.text("Sensitive nested settings")), 5_000))
        compose.runOnIdle { assertEquals(0, dismissed); nested = false }
        compose.waitForIdle()
        assertTrue(device.wait(Until.hasObject(By.text("Payment complete")), 5_000))
    }

    @Test fun privacyCoverUsesTheSameModalBoundaryAndRestoresTheScreen() {
        var covered by mutableStateOf(false)
        compose.setCashuContent {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Full-screen receipt") }
            if (covered) AppLockDialog { PrivacyCover() }
        }
        compose.runOnIdle { covered = true }
        compose.waitForIdle()
        assertFalse(device.hasObject(By.text("Full-screen receipt")))
        device.pressBack()
        compose.runOnIdle { assertTrue(covered); covered = false }
        compose.waitForIdle()
        assertTrue(device.wait(Until.hasObject(By.text("Full-screen receipt")), 5_000))
    }
    @Test fun cancelledAuthenticationReturnsFocusToTheGate() {
        var authenticating by mutableStateOf(false)
        compose.setCashuContent {
            AppLockDialog(isAuthenticating = authenticating) {
                AppLockGateContent(isAuthenticating = authenticating, onUnlock = { authenticating = true })
            }
            // Model a native authentication window taking focus, without using
            // a real device credential or biometric prompt in the test runner.
            if (authenticating) AlertDialog(
                onDismissRequest = { authenticating = false },
                title = { Text("Authentication challenge") },
                confirmButton = { Button(onClick = { authenticating = false }) { Text("Cancel challenge") } },
            )
        }
        compose.waitForIdle()
        device.findObject(By.text("Unlock")).click()
        compose.waitForIdle()
        assertTrue(device.wait(Until.hasObject(By.text("Authentication challenge")), 5_000))
        device.findObject(By.text("Cancel challenge")).click()
        compose.waitForIdle()
        assertTrue(device.wait(Until.hasObject(By.text("Wallet Locked")), 5_000))
        device.pressBack()
        assertTrue(device.hasObject(By.text("Wallet Locked")))
    }

}
