package org.cashu.wallet.Core

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

data class PriceState(
    val btcPrice: Double = 0.0,
    val currencyCode: String = "USD",
    val isEnabled: Boolean = false,
    val isFetching: Boolean = false,
    val lastUpdatedEpochMillis: Long? = null,
    val errorMessage: String? = null,
)

class PriceService(private val settingsStore: SettingsStore) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutableState = MutableStateFlow(loadStateFromStore())
    val state: StateFlow<PriceState> = mutableState.asStateFlow()
    private var refreshJob: Job? = null

    init {
        if (mutableState.value.isEnabled) startAutoRefresh()
    }

    fun syncFromSettings(refresh: Boolean = false) {
        val updated = loadStateFromStore().copy(
            isFetching = mutableState.value.isFetching,
            errorMessage = mutableState.value.errorMessage,
        )
        mutableState.value = updated
        if (updated.isEnabled) {
            startAutoRefresh()
        } else {
            stopAutoRefresh()
        }
        if (refresh && updated.isEnabled) refresh()
    }

    fun refresh() {
        scope.launch { refreshBitcoinPrice() }
    }

    suspend fun refreshBitcoinPrice(): Double? {
        syncFromSettings(refresh = false)
        val current = mutableState.value
        if (!current.isEnabled) return null
        mutableState.value = current.copy(isFetching = true, errorMessage = null)

        val result = runCatching {
            withContext(Dispatchers.IO) {
                fetchCoinbasePrice(current.currencyCode)
            }
        }

        return result.fold(
            onSuccess = { price ->
                val now = System.currentTimeMillis()
                settingsStore.setCachedPrice(price, current.currencyCode)
                settingsStore.setCachedPriceDate(now, current.currencyCode)
                mutableState.value = mutableState.value.copy(
                    btcPrice = price,
                    isFetching = false,
                    lastUpdatedEpochMillis = now,
                    errorMessage = null,
                )
                price
            },
            onFailure = { error ->
                mutableState.value = mutableState.value.copy(
                    isFetching = false,
                    errorMessage = error.message ?: "Could not fetch BTC price.",
                )
                null
            },
        )
    }

    private fun loadStateFromStore(): PriceState {
        val currency = settingsStore.priceCurrencyCode.ifBlank { settingsStore.bitcoinPriceCurrency }.uppercase()
        return PriceState(
            btcPrice = settingsStore.cachedPrice(currency) ?: 0.0,
            currencyCode = currency,
            isEnabled = settingsStore.priceEnabled || settingsStore.showFiatBalance,
            isFetching = false,
            lastUpdatedEpochMillis = settingsStore.cachedPriceDate(currency),
            errorMessage = null,
        )
    }

    private fun startAutoRefresh() {
        if (refreshJob?.isActive == true) return
        refreshJob = scope.launch {
            delay(1_000)
            while (isActive) {
                refreshBitcoinPrice()
                delay(60_000)
            }
        }
    }

    private fun stopAutoRefresh() {
        refreshJob?.cancel()
        refreshJob = null
    }

    private fun fetchCoinbasePrice(currency: String): Double {
        val connection = (URL("https://api.coinbase.com/v2/prices/BTC-$currency/spot").openConnection() as HttpURLConnection)
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        return try {
            if (connection.responseCode !in 200..299) error("Invalid response from Coinbase.")
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            Json.parseToJsonElement(body)
                .jsonObject["data"]
                ?.jsonObject
                ?.get("amount")
                ?.jsonPrimitive
                ?.content
                ?.toDoubleOrNull()
                ?: error("Could not parse price data.")
        } finally {
            connection.disconnect()
        }
    }
}
