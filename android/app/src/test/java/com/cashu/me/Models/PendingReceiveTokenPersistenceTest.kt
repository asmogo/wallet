package com.cashu.me.Models

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PendingReceiveTokenPersistenceTest {
    private val json = Json { encodeDefaults = true }

    @Test
    fun memoSurvivesPersistenceRoundTrip() {
        val original = pendingReceiveToken(memo = "Coffee from Alice")

        val restored = json.decodeFromString<PendingReceiveToken>(
            json.encodeToString(original),
        )

        assertEquals("Coffee from Alice", restored.memo)
        assertEquals(original, restored)
    }

    @Test
    fun legacyPendingReceiveWithoutMemoDefaultsToAbsent() {
        val restored = json.decodeFromString<PendingReceiveToken>(
            """
            {
              "tokenId": "pending",
              "token": "cashuAtoken",
              "amount": 21,
              "dateEpochMillis": 100,
              "mintUrl": "https://mint.example.com",
              "unit": "sat"
            }
            """.trimIndent(),
        )

        assertNull(restored.memo)
    }

    private fun pendingReceiveToken(memo: String?) = PendingReceiveToken(
        tokenId = "pending",
        token = "cashuAtoken",
        amount = 21,
        dateEpochMillis = 100,
        mintUrl = "https://mint.example.com",
        unit = "sat",
        memo = memo,
    )
}
