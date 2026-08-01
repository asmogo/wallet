package com.cashu.me.ui.settings

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppLockEnablementTest {
    @Test
    fun successfulAuthenticationEnablesAppLockOnlyAfterChallengeCompletes() = runBlocking {
        val events = mutableListOf<String>()
        var enabled = false

        enableAppLockAfterAuthentication(
            authenticate = {
                events += "authenticated"
                true
            },
            setEnabled = {
                enabled = it
                events += "persisted"
            },
        )

        assertTrue(enabled)
        assertEquals(listOf("authenticated", "persisted"), events)
    }

    @Test
    fun cancelledOrFailedAuthenticationLeavesAppLockDisabled() = runBlocking {
        var enabled = false

        enableAppLockAfterAuthentication(
            authenticate = { false },
            setEnabled = { enabled = it },
        )

        assertFalse(enabled)
    }
}
