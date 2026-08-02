package com.cashu.me.ui.shell

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShellIdleGateTest {
    @Test
    fun idleWhenEverySurfaceIsClearAndRuntimeReady() {
        assertTrue(
            shellIsIdleForInterrupt(
                isRuntimeReady = true,
                receiveDetailVisible = false,
                flowActive = false,
                scannerVisible = false,
                locked = false,
            ),
        )
    }

    @Test
    fun anyBusySurfaceDefersInterrupts() {
        assertFalse(
            shellIsIdleForInterrupt(
                isRuntimeReady = false,
                receiveDetailVisible = false,
                flowActive = false,
                scannerVisible = false,
                locked = false,
            ),
        )
        assertFalse(
            shellIsIdleForInterrupt(
                isRuntimeReady = true,
                receiveDetailVisible = true,
                flowActive = false,
                scannerVisible = false,
                locked = false,
            ),
        )
        assertFalse(
            shellIsIdleForInterrupt(
                isRuntimeReady = true,
                receiveDetailVisible = false,
                flowActive = true,
                scannerVisible = false,
                locked = false,
            ),
        )
        assertFalse(
            shellIsIdleForInterrupt(
                isRuntimeReady = true,
                receiveDetailVisible = false,
                flowActive = false,
                scannerVisible = true,
                locked = false,
            ),
        )
        assertFalse(
            shellIsIdleForInterrupt(
                isRuntimeReady = true,
                receiveDetailVisible = false,
                flowActive = false,
                scannerVisible = false,
                locked = true,
            ),
        )
    }
}
