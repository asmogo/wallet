package com.cashu.me.Core

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/** Commit local mint metadata only after the native removal succeeds. */
internal suspend fun removeMintWalletBeforeCommit(
    mintUrl: String,
    removeWalletIfSingleUnit: suspend (mintUrl: String) -> Boolean,
    commitMetadata: () -> Unit,
): Boolean {
    currentCoroutineContext().ensureActive()
    // Shield the native side effect and its local metadata commit from the
    // cancellation hand-off performed by cdkCall's withContext(IO). Once CDK
    // removes the wallet, metadata must follow before cancellation propagates.
    val nativeWalletExisted = withContext(NonCancellable) {
        val existed = removeWalletIfSingleUnit(mintUrl)
        commitMetadata()
        existed
    }
    currentCoroutineContext().ensureActive()
    return nativeWalletExisted
}
