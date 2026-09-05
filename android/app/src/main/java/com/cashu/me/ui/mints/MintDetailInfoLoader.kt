package com.cashu.me.ui.mints

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal enum class MintConnectionState(val label: String) {
    NotChecked("Not checked"),
    Checking("Checking…"),
    Online("Online"),
    Offline("Offline"),
}

/** Used from the UI coroutine scope; only the latest request may publish state. */
internal class MintDetailInfoLoader<Info : Any> {
    var info by mutableStateOf<Info?>(null)
        private set
    var connection by mutableStateOf(MintConnectionState.NotChecked)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    private var requestID = 0L

    suspend fun load(fetch: suspend () -> Info?) {
        currentCoroutineContext().ensureActive()
        val request = ++requestID
        connection = MintConnectionState.Checking
        errorMessage = null
        try {
            val fetched = fetch()
            currentCoroutineContext().ensureActive()
            if (request != requestID) return
            if (fetched == null) {
                connection = MintConnectionState.Offline
                errorMessage = "The mint did not respond."
            } else {
                info = fetched
                connection = MintConnectionState.Online
            }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            if (request != requestID) return
            connection = MintConnectionState.Offline
            errorMessage = error.userFacingWalletMessage
        } finally {
            // Cancellation is not evidence that the mint is offline. Do not let
            // cleanup from a superseded request stop a newer loading indicator.
            if (request == requestID && connection == MintConnectionState.Checking) {
                connection = MintConnectionState.NotChecked
            }
        }
    }
}
