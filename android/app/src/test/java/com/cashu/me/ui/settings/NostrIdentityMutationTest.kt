package com.cashu.me.ui.settings

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NostrIdentityMutationTest {
    @Test
    fun mutationFailuresKeepIdentityReassuranceWithoutRawStorageDetails() {
        NostrIdentityMutation.entries.forEach { mutation ->
            val message = mutation.failureMessage(IllegalStateException("Storage unavailable: internal/path nsec1private"))

            assertTrue(message, message.contains("current identity was not changed"))
            assertTrue(message, message.contains("key"))
            assertFalse(message, message.contains("internal/path"))
            assertFalse(message, message.contains("nsec1private"))
        }
    }
}
