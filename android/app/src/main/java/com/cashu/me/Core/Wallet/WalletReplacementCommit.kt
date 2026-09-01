package com.cashu.me.Core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

internal data class WalletReplacementCleanupStep(
    val description: String,
    val run: suspend () -> Unit,
)

/**
 * Keeps rollback resources alive until every fallible install step has
 * completed. Cleanup starts only after [installAndCommit] returns, and a
 * cleanup failure can therefore never roll a committed wallet back.
 */
internal suspend fun runWalletReplacementCommit(
    installAndCommit: suspend () -> Unit,
    rollback: suspend () -> Unit,
    cleanupSteps: List<WalletReplacementCleanupStep>,
    onCleanupFailure: (description: String, error: Throwable) -> Unit,
) {
    try {
        installAndCommit()
    } catch (failure: Throwable) {
        try {
            withContext(NonCancellable) { rollback() }
        } catch (rollbackFailure: Throwable) {
            failure.addSuppressed(rollbackFailure)
        }
        throw failure
    }

    cleanupSteps.forEach { step ->
        try {
            step.run()
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (error: Exception) {
            try {
                onCleanupFailure(step.description, error)
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (reportingFailure: Exception) {
                error.addSuppressed(reportingFailure)
            }
        }
    }
}
