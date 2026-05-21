package org.cashu.wallet.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsLegacySecretMigrationTest {
    @Test
    fun parserReadsSwiftNwcSecretsAndMetadataFallbacks() {
        val raw = """
            [
              {
                "id": "nwc-1",
                "walletPublicKey": "wallet-pub",
                "walletPrivateKey": "wallet-priv",
                "connectionSecret": "connection-secret",
                "connectionPublicKey": "connection-pub",
                "allowanceLeft": 2500
              }
            ]
        """.trimIndent()

        val record = LegacySettingsSecretParser.nwcConnections(raw).single()

        assertEquals("nwc-1", record.metadata.id)
        assertEquals("Wallet connection", record.metadata.name)
        assertEquals("wallet-pub", record.metadata.walletPublicKey)
        assertEquals("connection-pub", record.metadata.connectionPublicKey)
        assertEquals(2500L, record.metadata.allowanceSats)
        assertEquals("wallet-priv", record.walletPrivateKey)
        assertEquals("connection-secret", record.connectionSecret)
        assertTrue(record.hasLegacySecret)
        assertTrue(record.shouldRewriteMetadata)
    }

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
        val nwc = LegacySettingsSecretParser.nwcConnections(
            """
                [
                  {
                    "id": "nwc-1",
                    "name": "Wallet connection",
                    "walletPublicKey": "wallet-pub",
                    "walletPrivateKey": "legacy-wallet-priv",
                    "connectionSecret": "legacy-connection-secret",
                    "connectionPublicKey": "connection-pub",
                    "allowanceSats": 1000,
                    "createdAtEpochMillis": 1234
                  }
                ]
            """.trimIndent(),
        )
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
        val secureValues = mutableMapOf(
            LegacySettingsSecretMigrator.secureNWCWalletPrivateKey("nwc-1") to "existing-wallet-priv",
        )

        val migration = LegacySettingsSecretMigrator.migrate(
            nwcRecords = nwc,
            p2pkRecords = p2pk,
            loadSecret = secureValues::get,
            saveSecret = { key, value -> secureValues[key] = value },
        )

        assertEquals(
            "existing-wallet-priv",
            secureValues[LegacySettingsSecretMigrator.secureNWCWalletPrivateKey("nwc-1")],
        )
        assertEquals(
            "legacy-connection-secret",
            secureValues[LegacySettingsSecretMigrator.secureNWCConnectionSecret("nwc-1")],
        )
        assertEquals(
            "legacy-p2pk-private",
            secureValues[LegacySettingsSecretMigrator.secureP2PKPrivateKey("p2pk-1")],
        )
        assertNotNull(migration.nwcConnectionsToPersist)
        assertNotNull(migration.p2pkKeysToPersist)
        assertEquals("nwc-1", migration.nwcConnectionsToPersist?.single()?.id)
        assertEquals("p2pk-1", migration.p2pkKeysToPersist?.single()?.id)
    }
}
