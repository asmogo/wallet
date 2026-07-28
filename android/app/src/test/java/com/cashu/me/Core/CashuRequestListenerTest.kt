package com.cashu.me.Core

import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CashuRequestListenerTest {
    @Test
    fun paymentPayloadBuildsCashuATokenAndPreservesRequestId() {
        val result = CashuRequestListener.paymentPayloadToToken(
            """
            {
              "id": "request-1",
              "memo": "Thanks",
              "mint": "https://mint.example.com",
              "unit": "sat",
              "proofs": [{"amount":1,"id":"keyset","secret":"secret","C":"commitment"}]
            }
            """.trimIndent(),
        )

        assertEquals("request-1", result.requestId)
        assertTrue(result.token.startsWith("cashuA"))
        val payload = String(Base64.getUrlDecoder().decode(result.token.removePrefix("cashuA")), Charsets.UTF_8)
        val fields = Json.parseToJsonElement(payload).jsonObject
        val entry = fields["token"]!!.jsonArray.first().jsonObject
        assertEquals("https://mint.example.com", entry["mint"]!!.jsonPrimitive.content)
        assertEquals("sat", fields["unit"]!!.jsonPrimitive.content)
        assertEquals("Thanks", fields["memo"]!!.jsonPrimitive.content)
        assertEquals(1, entry["proofs"]!!.jsonArray.size)
    }

    @Test
    fun automaticClaimRequiresOptInAndPreviouslyTrustedMint() {
        assertFalse(CashuRequestListener.shouldAutoClaim(autoClaimEnabled = false, mintKnown = false))
        assertFalse(CashuRequestListener.shouldAutoClaim(autoClaimEnabled = false, mintKnown = true))
        assertFalse(CashuRequestListener.shouldAutoClaim(autoClaimEnabled = true, mintKnown = false))
        assertTrue(CashuRequestListener.shouldAutoClaim(autoClaimEnabled = true, mintKnown = true))
    }

    @Test
    fun heldAutomaticClaimRequiresListenerOwnershipAndKnownMint() {
        assertFalse(
            CashuRequestListener.shouldClaimHeldPayment(
                autoClaimEnabled = false,
                listenerHeld = true,
                mintKnown = true,
            ),
        )
        assertFalse(
            CashuRequestListener.shouldClaimHeldPayment(
                autoClaimEnabled = true,
                listenerHeld = false,
                mintKnown = true,
            ),
        )
        assertFalse(
            CashuRequestListener.shouldClaimHeldPayment(
                autoClaimEnabled = true,
                listenerHeld = true,
                mintKnown = false,
            ),
        )
        assertTrue(
            CashuRequestListener.shouldClaimHeldPayment(
                autoClaimEnabled = true,
                listenerHeld = true,
                mintKnown = true,
            ),
        )
    }

    @Test
    fun transientFailuresRemainRetryable() {
        assertFalse(
            CashuRequestListener.shouldMarkProcessed(
                CashuRequestListener.ClaimOutcome.TransientFailure,
            ),
        )
        assertTrue(
            CashuRequestListener.shouldMarkProcessed(
                CashuRequestListener.ClaimOutcome.Held,
            ),
        )
        assertTrue(
            CashuRequestListener.shouldMarkProcessed(
                CashuRequestListener.ClaimOutcome.Claimed,
            ),
        )
        assertTrue(
            CashuRequestListener.shouldMarkProcessed(
                CashuRequestListener.ClaimOutcome.Unclaimable,
            ),
        )
    }

    @Test
    fun listenerUsesFixedLookbackAndBoundedProcessedIds() {
        val now = 2_000_000L
        assertEquals(
            now - CashuRequestListener.LookbackWindowSeconds,
            CashuRequestListener.lookbackSince(now),
        )
        assertEquals(
            listOf("b", "c"),
            CashuRequestListener.appendProcessedId(
                current = listOf("a", "b"),
                id = "c",
                limit = 2,
            ),
        )
        assertEquals(
            listOf("a", "b"),
            CashuRequestListener.appendProcessedId(
                current = listOf("a", "b"),
                id = "b",
                limit = 2,
            ),
        )
    }
}
