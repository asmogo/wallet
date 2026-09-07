package com.cashu.me.Core

import com.cashu.me.Core.Wallet.userFacingWalletMessage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** A destructive operation is owned by the wallet, independent of its sheet. */
internal class WalletDeletionAction(
    private val launch: (suspend CoroutineScope.() -> Unit) -> Unit,
    private val delete: suspend () -> Unit,
) {
    private val mutableRunning = MutableStateFlow(false)
    val running = mutableRunning.asStateFlow()
    private val mutableError = MutableStateFlow<String?>(null)
    val error = mutableError.asStateFlow()

    fun submit() {
        if (!mutableRunning.compareAndSet(false, true)) return
        mutableError.value = null
        launch {
            try {
                delete()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                mutableError.value = error.userFacingWalletMessage
            } finally {
                mutableRunning.value = false
            }
        }
    }

    fun acknowledgeError(message: String) { mutableError.compareAndSet(message, null) }
}
