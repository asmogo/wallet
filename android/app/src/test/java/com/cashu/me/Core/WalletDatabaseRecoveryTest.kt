package com.cashu.me.Core

import java.io.File
import com.cashu.me.Core.Platform.WalletDatabaseFiles
import com.cashu.me.Core.Platform.WalletFileMove
import com.cashu.me.Core.Platform.WalletFileMoves
import com.cashu.me.Core.Platform.WalletReplacementFileOperations
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
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
            "malformed database schema (wallets)",
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

    @Test
    fun corruptedDatabaseBackupLaterMoveFailureRestoresDatabaseAndSidecars() {
        lateinit var failingSource: File
        val operations = operations(moveItem = { source, destination ->
            if (source == failingSource) throw ForcedMoveFailure()
            liveMove(source, destination)
        })
        val files = WalletDatabaseFiles(temporaryFolder.root, operations = operations)
        files.databaseFile.writeText("bad-db")
        val wal = File(files.databaseFile.absolutePath + "-wal").also {
            it.writeText("bad-wal")
        }
        val shm = File(files.databaseFile.absolutePath + "-shm").also {
            it.writeText("bad-shm")
        }
        failingSource = shm

        assertThrows(ForcedMoveFailure::class.java) {
            files.backupCorruptedDatabase()
        }

        assertEquals("bad-db", files.databaseFile.readText())
        assertEquals("bad-wal", wal.readText())
        assertEquals("bad-shm", shm.readText())
        assertNoMoveArtifacts(files.walletDirectory)
    }

    @Test
    fun corruptedDatabaseBackupFailureReportedAfterMoveRestoresEverySource() {
        lateinit var failingSource: File
        val operations = operations(moveItem = { source, destination ->
            liveMove(source, destination)
            if (source == failingSource) throw ForcedMoveFailure()
        })
        val files = WalletDatabaseFiles(temporaryFolder.root, operations = operations)
        files.databaseFile.writeText("bad-db")
        val wal = File(files.databaseFile.absolutePath + "-wal").also {
            it.writeText("bad-wal")
        }
        failingSource = wal

        assertThrows(ForcedMoveFailure::class.java) {
            files.backupCorruptedDatabase()
        }

        assertEquals("bad-db", files.databaseFile.readText())
        assertEquals("bad-wal", wal.readText())
        assertNoMoveArtifacts(files.walletDirectory)
    }

    @Test
    fun legacyMigrationMoveFailureRestoresSourcesAndExistingDestination() {
        lateinit var failingSource: File
        val operations = operations(moveItem = { source, destination ->
            if (source == failingSource) throw ForcedMoveFailure()
            liveMove(source, destination)
        })
        val files = WalletDatabaseFiles(temporaryFolder.root, operations = operations)
        val legacy = File(temporaryFolder.root, "cashu_wallet.db").also {
            it.writeText("legacy-db")
        }
        val wal = File(legacy.absolutePath + "-wal").also { it.writeText("legacy-wal") }
        val currentWal = File(files.databaseFile.absolutePath + "-wal").also {
            it.writeText("preexisting-current-wal")
        }
        failingSource = wal

        assertThrows(ForcedMoveFailure::class.java) {
            files.databasePathAfterLegacyMigration()
        }

        assertEquals("legacy-db", legacy.readText())
        assertEquals("legacy-wal", wal.readText())
        assertFalse(files.databaseFile.exists())
        assertEquals("preexisting-current-wal", currentWal.readText())
        assertNoMoveArtifacts(files.walletDirectory)
    }

    @Test
    fun committedMoveKeepsNewDestinationWhenCleanupFails() {
        val source = temporaryFolder.newFile("source.db").also { it.writeText("new") }
        val destination = temporaryFolder.newFile("destination.db").also { it.writeText("old") }
        val displaced = File(temporaryFolder.root, "destination.db.displaced")
        val operations = operations(
            removeItem = { throw ForcedDeleteFailure() },
        )

        WalletFileMoves.move(
            moves = listOf(WalletFileMove(source, destination)),
            operations = operations,
            displacedFile = { displaced },
        )

        assertFalse(source.exists())
        assertEquals("new", destination.readText())
        assertEquals("old", displaced.readText())
    }

    private fun assertNoMoveArtifacts(directory: File) {
        assertTrue(directory.listFiles().orEmpty().none { ".move-displaced." in it.name })
    }

    private fun operations(
        moveItem: (File, File) -> Unit = liveMove,
        removeItem: (File) -> Unit = { file -> check(file.deleteRecursively()) },
    ) = WalletReplacementFileOperations(
        exists = File::exists,
        moveItem = moveItem,
        removeItem = removeItem,
    )

    private val liveMove: (File, File) -> Unit = { source, destination ->
        check(source.renameTo(destination))
    }

    private class ForcedMoveFailure : RuntimeException()
    private class ForcedDeleteFailure : RuntimeException()
}
