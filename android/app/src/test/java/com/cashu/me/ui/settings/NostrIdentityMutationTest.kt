package com.cashu.me.ui.settings

import org.junit.Assert.assertTrue
import org.junit.Test

class NostrIdentityMutationTest {
    @Test
    fun everyMutationFailureNamesTheActionAndPromisesUnchangedIdentity() {
        NostrIdentityMutation.entries.forEach { mutation ->
            val message = mutation.failureMessage(IllegalStateException("Storage unavailable"))

            assertTrue(message, message.contains("current identity was not changed"))
            assertTrue(message, message.contains("Storage unavailable"))
        }
    }
}
