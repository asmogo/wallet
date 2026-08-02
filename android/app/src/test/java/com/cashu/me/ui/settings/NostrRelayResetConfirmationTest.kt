package com.cashu.me.ui.settings

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Reset is the only relay action that can discard several custom entries at
 * once, so it confirms — but only when there is something to discard.
 */
class NostrRelayResetConfirmationTest {
    private val defaults = listOf("wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net")

    @Test
    fun `a custom relay is worth confirming`() {
        assertTrue(shouldConfirmRelayReset(defaults + "wss://relay.mine.example", defaults))
    }

    @Test
    fun `a fully custom list is worth confirming`() {
        assertTrue(shouldConfirmRelayReset(listOf("wss://relay.mine.example"), defaults))
    }

    @Test
    fun `the untouched default list needs no confirmation`() {
        assertFalse(shouldConfirmRelayReset(defaults, defaults))
    }

    @Test
    fun `reordered defaults need no confirmation`() {
        assertFalse(shouldConfirmRelayReset(defaults.reversed(), defaults))
    }

    @Test
    fun `removing a default loses nothing that reset would not restore`() {
        assertFalse(shouldConfirmRelayReset(defaults.drop(1), defaults))
    }

    @Test
    fun `an empty list has nothing to discard`() {
        assertFalse(shouldConfirmRelayReset(emptyList(), defaults))
    }

    @Test
    fun `matching a default in another case is still a default`() {
        assertFalse(shouldConfirmRelayReset(listOf("WSS://RELAY.DAMUS.IO"), defaults))
    }
}
