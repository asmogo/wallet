package com.cashu.me.Core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class WalletReplacementCommitOrderTest {
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
    fun realCancellationBeforeCommitIsRethrownAfterSuspendingRollback() {
        var rollbackRan = false
        var cleanupRan = false

        assertThrows(CancellationException::class.java) {
            runBlocking {
                runWalletReplacementCommit(
                    installAndCommit = {
                        currentCoroutineContext().cancel(CancellationException("cancel replacement"))
                        yield()
                    },
                    rollback = {
                        // This suspension only completes when rollback runs in
                        // NonCancellable after the parent job is cancelled.
                        yield()
                        rollbackRan = true
                    },
                    cleanupSteps = listOf(
                        WalletReplacementCleanupStep("cleanup") { cleanupRan = true },
                    ),
                    onCleanupFailure = { _, _ -> Unit },
                )
            }
        }

        assertTrue(rollbackRan)
        assertFalse(cleanupRan)
    }
}
