package org.cashu.wallet.Core

import java.io.File
import org.cashu.wallet.Core.Platform.WalletDatabaseFiles
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WalletDatabaseRecoveryTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun recoveryIsAttemptedForDatabaseOpenErrors() {
        assertTrue(shouldAttemptWalletDatabaseRecovery(IllegalStateException("SQLite database is malformed")))
        assertTrue(shouldAttemptWalletDatabaseRecovery(IllegalStateException("WalletDB open failed")))
        assertTrue(shouldAttemptWalletDatabaseRecovery(IllegalStateException("database disk image is corrupt")))
    }

    @Test
    fun recoveryIsNotAttemptedForNonDatabaseErrors() {
        assertFalse(shouldAttemptWalletDatabaseRecovery(IllegalArgumentException("Invalid seed phrase.")))
        assertFalse(shouldAttemptWalletDatabaseRecovery(IllegalStateException("Couldn't reach the mint.")))
    }

    @Test
    fun legacyDatabaseMigrationMovesDatabaseAndSqliteSidecars() {
        val files = WalletDatabaseFiles(temporaryFolder.root)
        val legacy = File(temporaryFolder.root, "cashu_wallet.db").also { it.writeText("legacy-db") }
        val legacySidecars = listOf("-wal", "-shm", "-journal").map { suffix ->
            File(legacy.absolutePath + suffix).also { it.writeText("legacy$suffix") }
        }

        val migratedPath = files.databasePathAfterLegacyMigration()

        assertEquals(files.databaseFile.absolutePath, migratedPath)
        assertFalse(legacy.exists())
        legacySidecars.forEach { assertFalse(it.exists()) }
        assertEquals("legacy-db", files.databaseFile.readText())
        listOf("-wal", "-shm", "-journal").forEach { suffix ->
            assertEquals("legacy$suffix", File(files.databaseFile.absolutePath + suffix).readText())
        }
    }

    @Test
    fun legacyDatabaseMigrationDoesNotOverwriteCurrentDatabase() {
        val files = WalletDatabaseFiles(temporaryFolder.root)
        files.databaseFile.writeText("current-db")
        val legacy = File(temporaryFolder.root, "cashu_wallet.db").also { it.writeText("legacy-db") }

        files.databasePathAfterLegacyMigration()

        assertEquals("current-db", files.databaseFile.readText())
        assertTrue(legacy.exists())
        assertEquals("legacy-db", legacy.readText())
    }

    @Test
    fun corruptedDatabaseBackupMovesDatabaseAndSqliteSidecars() {
        val files = WalletDatabaseFiles(temporaryFolder.root)
        files.databaseFile.writeText("bad-db")
        listOf("-wal", "-shm", "-journal").forEach { suffix ->
            File(files.databaseFile.absolutePath + suffix).writeText("bad$suffix")
        }

        val backup = files.backupCorruptedDatabase()

        assertNotNull(backup)
        val backupFile = requireNotNull(backup)
        assertFalse(files.databaseFile.exists())
        assertEquals("bad-db", backupFile.readText())
        listOf("-wal", "-shm", "-journal").forEach { suffix ->
            assertFalse(File(files.databaseFile.absolutePath + suffix).exists())
            assertEquals("bad$suffix", File(backupFile.absolutePath + suffix).readText())
        }
    }
}
