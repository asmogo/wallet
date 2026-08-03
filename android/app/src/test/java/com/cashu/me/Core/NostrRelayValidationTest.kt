package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Relay input used to be accepted or dropped silently, so the Add-relay error
 * branch was unreachable. These pin the rules to iOS's.
 */
class NostrRelayValidationTest {
    private val existing = listOf("wss://relay.damus.io", "wss://nos.lol")

    @Test
    fun `wss relay is accepted`() {
        assertEquals(
            RelayAddResult.Added("wss://relay.example.com"),
            validateNostrRelay("wss://relay.example.com", existing),
        )
    }

    @Test
    fun `plaintext ws relay is accepted`() {
        assertEquals(
            RelayAddResult.Added("ws://localhost:7000"),
            validateNostrRelay("ws://localhost:7000", existing),
        )
    }

    @Test
    fun `non websocket schemes are rejected with the shared copy`() {
        listOf("https://relay.example.com", "relay.example.com", "wss:/typo.example.com").forEach {
            assertEquals(
                "rejected $it",
                RelayAddResult.Rejected(RelayAddResult.InvalidScheme),
                validateNostrRelay(it, existing),
            )
        }
    }

    @Test
    fun `scheme check ignores case`() {
        assertEquals(
            RelayAddResult.Added("WSS://Relay.Example.com"),
            validateNostrRelay("WSS://Relay.Example.com", existing),
        )
    }

    @Test
    fun `duplicates are rejected regardless of case`() {
        assertEquals(
            RelayAddResult.Rejected(RelayAddResult.Duplicate),
            validateNostrRelay("WSS://RELAY.DAMUS.IO", existing),
        )
    }

    @Test
    fun `surrounding whitespace is trimmed before validating and storing`() {
        assertEquals(
            RelayAddResult.Added("wss://relay.example.com"),
            validateNostrRelay("  wss://relay.example.com  ", existing),
        )
    }

    @Test
    fun `an accepted relay keeps the casing the user typed`() {
        val result = validateNostrRelay("wss://Relay.Example.com", emptyList())
        assertEquals(RelayAddResult.Added("wss://Relay.Example.com"), result)
    }

    @Test
    fun `blank input is a silent no-op rather than an error`() {
        assertNull(validateNostrRelay("", existing))
        assertNull(validateNostrRelay("   ", existing))
    }
}
