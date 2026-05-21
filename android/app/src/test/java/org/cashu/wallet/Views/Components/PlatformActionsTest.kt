package org.cashu.wallet.Views.Components

import org.junit.Assert.assertEquals
import org.junit.Test

class PlatformActionsTest {
    @Test
    fun cashuTokenShareContentAddsSchemeOnce() {
        assertEquals("cashu:cashuA-test", cashuTokenShareContent("cashuA-test"))
        assertEquals("cashu:cashuA-test", cashuTokenShareContent("cashu:cashuA-test"))
    }
}
