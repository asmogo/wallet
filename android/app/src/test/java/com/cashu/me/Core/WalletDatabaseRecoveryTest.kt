package com.cashu.me.Core

import java.io.File
import com.cashu.me.Core.Platform.WalletDatabaseFiles
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
    fun recoveryIsAttemptedOnlyForExplicitCorruptionErrors() {
        listOf(
            "SQLite error SQLITE_CORRUPT: database disk image is malformed",
            "SQLite error SQLITE_NOTADB: file is not a database",
            "database disk image is corrupt",
        ).forEach { message ->
            assertTrue(message, shouldAttemptWalletDatabaseRecovery(IllegalStateException(message)))
        }
    }

    @Test
    fun recoveryIsNotAttemptedForTransientPermissionOrIoErrors() {
        listOf(
            "SQLite database is locked",
            "SQLite database is busy",
            "unable to open database file",
            "attempt to write a readonly database",
            "permission denied while opening WalletDB",
            "SQLite disk I/O error",
            "WalletDB open failed",
            "Invalid seed phrase.",
            "Couldn't reach the mint.",
        ).forEach { message ->
            assertFalse(message, shouldAttemptWalletDatabaseRecovery(IllegalStateException(message)))
        }
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
