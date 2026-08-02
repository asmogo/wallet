package com.cashu.me.ui.navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BackNavigationPolicyTest {
    @Test
    fun shellBackPrioritizesTopmostOverlay() {
        assertEquals(
            ShellBackAction.CloseReceiveDetail,
            shellBackAction(receiveDetailVisible = true, scannerVisible = true),
        )
        assertEquals(
            ShellBackAction.CloseScanner,
            shellBackAction(receiveDetailVisible = false, scannerVisible = true),
        )
        assertNull(shellBackAction(receiveDetailVisible = false, scannerVisible = false))
    }

    @Test
    fun connectMintBackUnwindsInSheetStepsBeforeClosing() {
        assertEquals(ConnectMintBackAction.ReturnToPicker, connectMintBackAction(onPickerStep = false))
        assertEquals(ConnectMintBackAction.Close, connectMintBackAction(onPickerStep = true))
    }
}
