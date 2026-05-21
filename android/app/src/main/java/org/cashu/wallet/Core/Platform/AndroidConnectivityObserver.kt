package org.cashu.wallet.Core.Platform

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.cashu.wallet.Core.AppLogger

enum class ConnectivityStatus {
    Online,
    Offline,
    Unknown,
}

data class ConnectivityState(
    val status: ConnectivityStatus = ConnectivityStatus.Unknown,
    val isMetered: Boolean? = null,
) {
    val displayText: String
        get() = when (status) {
            ConnectivityStatus.Online -> if (isMetered == true) "Online (metered)" else "Online"
            ConnectivityStatus.Offline -> "Offline"
            ConnectivityStatus.Unknown -> "Unknown"
        }
}

class AndroidConnectivityObserver(context: Context) {
    private val connectivityManager =
        context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val mutableState = MutableStateFlow(currentState())
    val state: StateFlow<ConnectivityState> = mutableState.asStateFlow()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            refresh()
        }

        override fun onLost(network: Network) {
            refresh()
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            refresh()
        }
    }

    init {
        runCatching {
            connectivityManager.registerNetworkCallback(
                NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build(),
                callback,
            )
        }.onFailure { error ->
            AppLogger.network.error("Connectivity callback registration failed", error)
        }
        refresh()
    }

    fun refresh() {
        mutableState.value = currentState()
    }

    fun stop() {
        runCatching { connectivityManager.unregisterNetworkCallback(callback) }
    }

    @SuppressLint("MissingPermission")
    private fun currentState(): ConnectivityState {
        val activeNetwork = connectivityManager.activeNetwork ?: return connectivityStateFromCapabilities(
            hasInternet = false,
            isMetered = null,
        )
        val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
        return connectivityStateFromCapabilities(
            hasInternet = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true,
            isMetered = connectivityManager.isActiveNetworkMetered,
        )
    }
}

internal fun connectivityStateFromCapabilities(
    hasInternet: Boolean,
    isMetered: Boolean?,
): ConnectivityState = ConnectivityState(
    status = if (hasInternet) ConnectivityStatus.Online else ConnectivityStatus.Offline,
    isMetered = isMetered,
)
