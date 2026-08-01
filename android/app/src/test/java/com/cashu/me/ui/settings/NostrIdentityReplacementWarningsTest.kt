package com.cashu.me.ui.settings

import org.junit.Assert.assertTrue
import org.junit.Test

class NostrIdentityReplacementWarningsTest {
    @Test
    fun everyReplacementWarningNamesAllIdentityConsequences() {
        val warnings = listOf(
            NostrIdentityReplacementWarnings.Generate,
            NostrIdentityReplacementWarnings.Import,
            NostrIdentityReplacementWarnings.Reset,
            NostrIdentityReplacementWarnings.switchTo("Custom Key"),
        )

        warnings.forEach { warning ->
            assertTrue(warning.contains("Lightning address will change"))
            assertTrue(warning.contains("Nostr apps and messages will use a different identity"))
            assertTrue(warning.contains("old") && warning.contains("replaced"))
        }
    }
}
