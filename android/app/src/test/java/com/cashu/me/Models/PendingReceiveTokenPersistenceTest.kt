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
    fun distinctTokensWithTheSamePrefixSurviveSaveAndReload() {
        val prefix = "cashuA" + "a".repeat(80)
        val first = pendingReceiveToken(null).copy(token = prefix + "first", tokenId = prefix.take(64))
        val second = first.copy(token = prefix + "second")
        val saved = PendingReceiveToken.upsert(listOf(first), second)
        val restored = json.decodeFromString<List<PendingReceiveToken>>(json.encodeToString(saved))
        assertEquals(listOf(first.token, second.token), restored.map { it.token })
        org.junit.Assert.assertNotEquals(restored[0].id, restored[1].id)
    }

    @Test
    fun receivingTheSameLegacyTokenAgainUpdatesWithoutDuplicatingIt() {
        val legacy = pendingReceiveToken(null)
        val saved = PendingReceiveToken.upsert(listOf(legacy), legacy.copy(memo = "Updated"))
        assertEquals(1, saved.size)
        assertEquals("Updated", saved.single().memo)
        assertEquals(PendingReceiveToken.idFor(legacy.token), saved.single().id)
    }

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
