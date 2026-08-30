package com.cashu.me.Core

import com.cashu.me.Core.Platform.WalletDatabaseFiles
import com.cashu.me.Core.Platform.WalletFileBackup
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WalletReplacementCommitOrderTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun failureImmediatelyBeforeCommitRollsBackWithResourcesIntact() {
        var oldSecretsIntact = true
        var databaseBackupIntact = true
        var newStateDurable = false
        var cleanupRan = false
        val events = mutableListOf<String>()
        val failure = IllegalStateException("injected before commit")

        val thrown = assertThrows(IllegalStateException::class.java) {
            runBlocking {
                runWalletReplacementCommit(
                    installAndCommit = {
                        events += "new seed/repository/cache/onboarding durable"
                        newStateDurable = true
                        assertTrue(oldSecretsIntact)
                        assertTrue(databaseBackupIntact)
                        throw failure
                    },
                    rollback = {
                        events += "rollback"
                        assertTrue(oldSecretsIntact)
                        assertTrue(databaseBackupIntact)
                        newStateDurable = false
                    },
                    cleanupSteps = listOf(
                        WalletReplacementCleanupStep("old wallet secrets") {
                            cleanupRan = true
                            oldSecretsIntact = false
                        },
                        WalletReplacementCleanupStep("wallet database backups") {
                            cleanupRan = true
                            databaseBackupIntact = false
                        },
                    ),
                    onCleanupFailure = { _, _ -> error("cleanup must not run") },
                )
            }
        }

        assertSame(failure, thrown)
        assertEquals(
            listOf("new seed/repository/cache/onboarding durable", "rollback"),
            events,
        )
        assertFalse(newStateDurable)
        assertTrue(oldSecretsIntact)
        assertTrue(databaseBackupIntact)
        assertFalse(cleanupRan)
    }

    @Test
    fun cleanupFailureAfterCommitIsReportedWithoutRollback() = runBlocking {
        var committed = false
        var rollbackCount = 0
        var oldSecretsIntact = true
        var databaseBackupIntact = true
        val reported = mutableListOf<String>()

        runWalletReplacementCommit(
            installAndCommit = { committed = true },
            rollback = { rollbackCount += 1 },
            cleanupSteps = listOf(
                WalletReplacementCleanupStep("old wallet secrets") {
                    assertTrue(committed)
                    oldSecretsIntact = false
                    throw IllegalStateException("injected cleanup failure")
                },
                WalletReplacementCleanupStep("wallet database backups") {
                    assertTrue(committed)
                    databaseBackupIntact = false
                },
            ),
            onCleanupFailure = { description, _ -> reported += description },
        )

        assertTrue(committed)
        assertEquals(0, rollbackCount)
        assertFalse(oldSecretsIntact)
        assertFalse(databaseBackupIntact)
        assertEquals(listOf("old wallet secrets"), reported)
    }

    @Test
    fun cancellationBeforeCommitIsRethrownAfterRollback() {
        val cancellation = CancellationException("cancel replacement")
        var rollbackRan = false
        var cleanupRan = false

        val thrown = assertThrows(CancellationException::class.java) {
            runBlocking {
                runWalletReplacementCommit(
                    installAndCommit = { throw cancellation },
                    rollback = { rollbackRan = true },
                    cleanupSteps = listOf(
                        WalletReplacementCleanupStep("cleanup") { cleanupRan = true },
                    ),
                    onCleanupFailure = { _, _ -> Unit },
                )
            }
        }

        assertSame(cancellation, thrown)
        assertTrue(rollbackRan)
        assertFalse(cleanupRan)
    }

    @Test
    fun failedDatabaseBackupRenamePreservesLiveWallet() {
        val mover = FailingMove(failAt = 1)
        val files = WalletDatabaseFiles(temporaryFolder.root, moveFile = mover::move)
        files.databaseFile.writeText("live-wallet")

        assertThrows(IOException::class.java) {
            files.backupWalletDatabaseFiles()
        }

        assertEquals("live-wallet", files.databaseFile.readText())
        assertTrue(
            temporaryFolder.root.listFiles().orEmpty().none { ".replacing." in it.name },
        )
    }

    @Test
    fun laterDatabaseRestoreFailureRollsBackEarlierRestore() {
        val firstOriginal = File(temporaryFolder.root, "first.db").also { it.writeText("live-first") }
        val firstBackup = File(temporaryFolder.root, "first.db.backup").also { it.writeText("old-first") }
        val secondOriginal = File(temporaryFolder.root, "second.db").also { it.writeText("live-second") }
        val secondBackup = File(temporaryFolder.root, "second.db.backup").also { it.writeText("old-second") }
        val mover = FailingMove(failAt = 4)
        val files = WalletDatabaseFiles(temporaryFolder.root, moveFile = mover::move)

        assertThrows(IOException::class.java) {
            files.restoreWalletFileBackups(
                listOf(
                    WalletFileBackup(firstOriginal, firstBackup),
                    WalletFileBackup(secondOriginal, secondBackup),
                ),
            )
        }

        assertEquals("live-first", firstOriginal.readText())
        assertEquals("old-first", firstBackup.readText())
        assertEquals("live-second", secondOriginal.readText())
        assertEquals("old-second", secondBackup.readText())
        assertTrue(
            temporaryFolder.root.listFiles().orEmpty().none { ".restore-displaced." in it.name },
        )
    }

    @Test
    fun failedRealDatabaseCleanupIsReportedAfterCommitWithoutRollback() = runBlocking {
        val originalFiles = WalletDatabaseFiles(temporaryFolder.root)
        originalFiles.databaseFile.writeText("old-wallet")
        val backups = originalFiles.backupWalletDatabaseFiles()
        originalFiles.databaseFile.writeText("committed-wallet")
        val failingCleanupFiles = WalletDatabaseFiles(
            temporaryFolder.root,
            deleteFile = { false },
        )
        var committed = false
        var rollbackCount = 0
        val reported = mutableListOf<String>()

        runWalletReplacementCommit(
            installAndCommit = { committed = true },
            rollback = { rollbackCount += 1 },
            cleanupSteps = listOf(
                WalletReplacementCleanupStep("wallet database backups") {
                    failingCleanupFiles.removeWalletFileBackups(backups)
                },
            ),
            onCleanupFailure = { description, _ -> reported += description },
        )

        assertTrue(committed)
        assertEquals(0, rollbackCount)
        assertEquals(listOf("wallet database backups"), reported)
        assertEquals("committed-wallet", originalFiles.databaseFile.readText())
        assertTrue(backups.single().backup.exists())
        assertEquals("old-wallet", File(backups.single().backup, "wallet.db").readText())
    }

    private class FailingMove(
        private val failAt: Int,
    ) {
        private var attempts = 0

        fun move(source: File, destination: File): Boolean {
            attempts += 1
            return attempts != failAt && source.renameTo(destination)
        }
    }
}
