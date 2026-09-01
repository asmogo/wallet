package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsLegacySecretMigrationTest {
    @Test
    fun parserReadsSwiftP2PKSecretAndMetadataFallbacks() {
        val raw = """
            [
              {
                "id": "p2pk-1",
                "publicKey": "02${"a".repeat(64)}",
                "privateKey": "private-key",
                "used": true,
                "usedCount": 3
              }
            ]
        """.trimIndent()

        val record = LegacySettingsSecretParser.p2pkKeys(raw).single()

        assertEquals("p2pk-1", record.metadata.id)
        assertEquals("P2PK key", record.metadata.label)
        assertEquals("private-key", record.privateKey)
        assertTrue(record.metadata.used)
        assertEquals(3, record.metadata.usedCount)
        assertTrue(record.hasLegacySecret)
        assertTrue(record.shouldRewriteMetadata)
    }

    @Test
    fun parserLeavesCurrentMetadataOnlyRowsAlone() {
        val raw = """
            [
              {
                "id": "p2pk-2",
                "publicKey": "02${"b".repeat(64)}",
                "label": "Stored key",
                "createdAtEpochMillis": 1234,
                "used": false,
                "usedCount": 0
              }
            ]
        """.trimIndent()

        val record = LegacySettingsSecretParser.p2pkKeys(raw).single()

        assertEquals("Stored key", record.metadata.label)
        assertFalse(record.hasLegacySecret)
        assertFalse(record.shouldRewriteMetadata)
    }

    @Test
    fun migratorSavesLegacySecretsWithoutOverwritingExistingSecureValues() {
        val p2pk = LegacySettingsSecretParser.p2pkKeys(
            """
                [
                  {
                    "id": "p2pk-1",
                    "publicKey": "02${"c".repeat(64)}",
                    "privateKey": "legacy-p2pk-private",
                    "used": false,
                    "usedCount": 0
                  },
                  {
                    "id": "p2pk-2",
                    "publicKey": "02${"d".repeat(64)}",
                    "privateKey": "legacy-p2pk-private-2",
                    "used": false,
                    "usedCount": 0
                  }
                ]
            """.trimIndent(),
        )
        val secureValues = mutableMapOf(
            LegacySettingsSecretMigrator.secureP2PKPrivateKey("p2pk-1") to "existing-p2pk-private",
        )

        val migration = LegacySettingsSecretMigrator.migrate(
            p2pkRecords = p2pk,
            loadSecret = secureValues::get,
            saveSecret = { key, value -> secureValues[key] = value },
            isUsableSecret = { _, _ -> true },
        )

        assertEquals(
            "existing-p2pk-private",
            secureValues[LegacySettingsSecretMigrator.secureP2PKPrivateKey("p2pk-1")],
        )
        assertEquals(
            "legacy-p2pk-private-2",
            secureValues[LegacySettingsSecretMigrator.secureP2PKPrivateKey("p2pk-2")],
        )
        assertNotNull(migration.p2pkKeysToPersist)
        assertEquals(listOf("p2pk-1", "p2pk-2"), migration.p2pkKeysToPersist?.map { it.id })
        assertTrue(migration.pendingLegacySecrets.isEmpty())
    }

    @Test
    fun migratorRetainsUsableLegacySecretOnlyWhenSecureWriteFails() {
        val p2pk = LegacySettingsSecretParser.p2pkKeys(
            """
                [
                  {
                    "id": "p2pk-1",
                    "publicKey": "02${"c".repeat(64)}",
                    "privateKey": "legacy-p2pk-private",
                    "used": false,
                    "usedCount": 0
                  }
                ]
            """.trimIndent(),
        )

        val migration = LegacySettingsSecretMigrator.migrate(
            p2pkRecords = p2pk,
            loadSecret = { null },
            saveSecret = { _, _ -> error("secure storage unavailable") },
            isUsableSecret = { _, secret -> secret == "legacy-p2pk-private" },
        )

        assertEquals(
            mapOf("p2pk-1" to "legacy-p2pk-private"),
            migration.pendingLegacySecrets,
        )
    }

    @Test
    fun migratorDoesNotRetainMalformedLegacySecret() {
        val p2pk = LegacySettingsSecretParser.p2pkKeys(
            """
                [
                  {
                    "id": "p2pk-1",
                    "publicKey": "02${"c".repeat(64)}",
                    "privateKey": "not-the-matching-key",
                    "used": false,
                    "usedCount": 0
                  }
                ]
            """.trimIndent(),
        )

        val migration = LegacySettingsSecretMigrator.migrate(
            p2pkRecords = p2pk,
            loadSecret = { null },
            saveSecret = { _, _ -> error("must not be called") },
            isUsableSecret = { _, _ -> false },
        )

        assertTrue(migration.pendingLegacySecrets.isEmpty())
        assertNotNull(migration.p2pkKeysToPersist)
    }
}
