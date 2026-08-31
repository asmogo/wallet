package com.cashu.me.Core

import com.cashu.me.Core.Platform.WalletFileBackup
import com.cashu.me.Core.Platform.WalletReplacementFileOperations
import com.cashu.me.Core.Platform.WalletReplacementFiles
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WalletReplacementSafetyTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private class ForcedMoveFailure : RuntimeException()
    private class ForcedSeedFailure : RuntimeException()

    private val liveMove: (File, File) -> Unit = { source, destination ->
        check(source.renameTo(destination))
    }

    private fun operations(
        moveItem: (File, File) -> Unit = liveMove,
    ) = WalletReplacementFileOperations(
        exists = File::exists,
        moveItem = moveItem,
        removeItem = { file -> check(!file.exists() || file.deleteRecursively()) },
    )

    @Test
    fun partialBackupFailureRestoresEveryMovedOriginal() {
        val first = temporaryFolder.newFile("first.db").also { it.writeText("first") }
        val second = temporaryFolder.newFile("second.db").also { it.writeText("second") }
        var forwardMoveCount = 0
        val operations = operations { source, destination ->
            if (!source.name.endsWith(".backup")) {
                forwardMoveCount += 1
                if (forwardMoveCount == 2) throw ForcedMoveFailure()
            }
            liveMove(source, destination)
        }

        assertThrows(ForcedMoveFailure::class.java) {
            WalletReplacementFiles.backup(
                files = listOf(first, second),
                operations = operations,
                backupFile = { File(it.parentFile, "${it.name}.backup") },
            )
        }

        assertEquals("first", first.readText())
        assertEquals("second", second.readText())
        assertFalse(File(first.parentFile, "${first.name}.backup").exists())
    }

    @Test
    fun partialBackupFailureReportedAfterMoveRestoresCurrentOriginal() {
        val first = temporaryFolder.newFile("first.db").also { it.writeText("first") }
        val second = temporaryFolder.newFile("second.db").also { it.writeText("second") }
        val operations = operations { source, destination ->
            liveMove(source, destination)
            if (source == second) throw ForcedMoveFailure()
        }

        assertThrows(ForcedMoveFailure::class.java) {
            WalletReplacementFiles.backup(
                files = listOf(first, second),
                operations = operations,
                backupFile = { File(it.parentFile, "${it.name}.backup") },
            )
        }

        assertEquals("first", first.readText())
        assertEquals("second", second.readText())
        assertFalse(File(first.parentFile, "${first.name}.backup").exists())
        assertFalse(File(second.parentFile, "${second.name}.backup").exists())
    }

    @Test
    fun missingBackupNeverDisplacesReplacementDatabase() {
        val original = temporaryFolder.newFile("wallet.db").also { it.writeText("replacement") }
        val missingBackup = File(original.parentFile, "wallet.db.backup")

        assertThrows(Exception::class.java) {
            WalletReplacementFiles.restore(
                files = listOf(original),
                backups = listOf(WalletFileBackup(original, missingBackup)),
                displacedFile = { File(it.parentFile, "${it.name}.displaced") },
            )
        }

        assertEquals("replacement", original.readText())
    }

    @Test
    fun committedRestoreRemovesReplacementWithoutAnOriginalBackup() {
        val replacement = temporaryFolder.newFile("wallet.db").also { it.writeText("replacement") }

        WalletReplacementFiles.restore(
            files = listOf(replacement),
            backups = emptyList(),
            displacedFile = { File(it.parentFile, "${it.name}.displaced") },
        )

        assertFalse(replacement.exists())
    }

    @Test
    fun restoreMoveFailurePutsReplacementDatabaseBack() {
        val original = temporaryFolder.newFile("wallet.db").also { it.writeText("replacement") }
        val backup = temporaryFolder.newFile("wallet.db.backup").also { it.writeText("original") }
        var moveCount = 0
        val operations = operations { source, destination ->
            moveCount += 1
            if (moveCount == 2) throw ForcedMoveFailure()
            liveMove(source, destination)
        }

        assertThrows(ForcedMoveFailure::class.java) {
            WalletReplacementFiles.restore(
                files = listOf(original),
                backups = listOf(WalletFileBackup(original, backup)),
                operations = operations,
                displacedFile = { File(it.parentFile, "${it.name}.displaced") },
            )
        }

        assertEquals("replacement", original.readText())
        assertEquals("original", backup.readText())
    }

    @Test
    fun displacementFailureReportedAfterMoveRestoresReplacement() {
        val original = temporaryFolder.newFile("wallet.db").also { it.writeText("replacement") }
        val backup = temporaryFolder.newFile("wallet.db.backup").also { it.writeText("original") }
        val displaced = File(original.parentFile, "wallet.db.displaced")
        val operations = operations { source, destination ->
            liveMove(source, destination)
            if (source == original && destination == displaced) throw ForcedMoveFailure()
        }

        assertThrows(ForcedMoveFailure::class.java) {
            WalletReplacementFiles.restore(
                files = listOf(original),
                backups = listOf(WalletFileBackup(original, backup)),
                operations = operations,
                displacedFile = { displaced },
            )
        }

        assertEquals("replacement", original.readText())
        assertEquals("original", backup.readText())
        assertFalse(displaced.exists())
    }

    @Test
    fun restoreFailureReportedAfterMoveRestoresReplacementAndBackup() {
        val original = temporaryFolder.newFile("wallet.db").also { it.writeText("replacement") }
        val backup = temporaryFolder.newFile("wallet.db.backup").also { it.writeText("original") }
        val displaced = File(original.parentFile, "wallet.db.displaced")
        var didFail = false
        val operations = operations { source, destination ->
            liveMove(source, destination)
            if (source == backup && !didFail) {
                didFail = true
                throw ForcedMoveFailure()
            }
        }

        assertThrows(ForcedMoveFailure::class.java) {
            WalletReplacementFiles.restore(
                files = listOf(original),
                backups = listOf(WalletFileBackup(original, backup)),
                operations = operations,
                displacedFile = { displaced },
            )
        }

        assertEquals("replacement", original.readText())
        assertEquals("original", backup.readText())
        assertFalse(displaced.exists())
    }

    @Test
    fun seedCommitFailureRollsFilesAndSeedForwardToReplacement() {
        val original = temporaryFolder.newFile("wallet.db").also { it.writeText("replacement") }
        val backup = temporaryFolder.newFile("wallet.db.backup").also { it.writeText("original") }
        val displaced = File(original.parentFile, "wallet.db.displaced")
        var activeSeed = "replacement seed"

        assertThrows(ForcedSeedFailure::class.java) {
            WalletReplacementFiles.restore(
                files = listOf(original),
                backups = listOf(WalletFileBackup(original, backup)),
                displacedFile = { displaced },
                beforeCommit = {
                    activeSeed = "original seed"
                    throw ForcedSeedFailure()
                },
                onRollback = {
                    activeSeed = "replacement seed"
                },
            )
        }

        assertEquals("replacement seed", activeSeed)
        assertEquals("replacement", original.readText())
        assertEquals("original", backup.readText())
        assertFalse(displaced.exists())
    }

    @Test
    fun laterRestoreFailureRestoresEveryReplacementAndBackup() {
        val firstOriginal = temporaryFolder.newFile("first.db").also { it.writeText("new first") }
        val firstBackup = temporaryFolder.newFile("first.db.backup").also { it.writeText("old first") }
        val secondOriginal = temporaryFolder.newFile("second.db").also { it.writeText("new second") }
        val secondBackup = temporaryFolder.newFile("second.db.backup").also { it.writeText("old second") }
        var backupMoveCount = 0
        val operations = operations { source, destination ->
            if (source.name.endsWith(".backup")) {
                backupMoveCount += 1
                if (backupMoveCount == 2) throw ForcedMoveFailure()
            }
            liveMove(source, destination)
        }

        assertThrows(ForcedMoveFailure::class.java) {
            WalletReplacementFiles.restore(
                files = listOf(firstOriginal, secondOriginal),
                backups = listOf(
                    WalletFileBackup(firstOriginal, firstBackup),
                    WalletFileBackup(secondOriginal, secondBackup),
                ),
                operations = operations,
                displacedFile = { File(it.parentFile, "${it.name}.displaced") },
            )
        }

        assertEquals(2, backupMoveCount)
        assertEquals("new first", firstOriginal.readText())
        assertEquals("old first", firstBackup.readText())
        assertEquals("new second", secondOriginal.readText())
        assertEquals("old second", secondBackup.readText())
        assertFalse(File(firstOriginal.parentFile, "${firstOriginal.name}.displaced").exists())
        assertFalse(File(secondOriginal.parentFile, "${secondOriginal.name}.displaced").exists())
    }
}
