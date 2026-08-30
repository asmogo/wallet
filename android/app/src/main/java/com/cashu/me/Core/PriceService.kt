package com.cashu.me.Core

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.CancellationException
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

interface PriceSettingsStore {
    var showFiatBalance: Boolean
    var bitcoinPriceCurrency: String
    var priceEnabled: Boolean
    var priceCurrencyCode: String

    fun cachedPrice(currency: String): Double?
    fun setCachedPrice(price: Double, currency: String)
    fun cachedPriceDate(currency: String): Long?
    fun setCachedPriceDate(epochMillis: Long, currency: String)
}

class PriceService internal constructor(
    private val settingsStore: PriceSettingsStore,
    private val priceFetcher: suspend (String) -> Double = { currency ->
        withContext(Dispatchers.IO) { fetchCoinbasePrice(currency) }
    },
    private val nowEpochMillis: () -> Long = System::currentTimeMillis,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    private val enableAutoRefresh: Boolean = true,
) {
    private val mutableState = MutableStateFlow(loadStateFromStore())
    val state: StateFlow<PriceState> = mutableState.asStateFlow()
    private var refreshJob: Job? = null
    private val requestLock = Any()
    private var requestGeneration = 0L

    init {
        if (enableAutoRefresh && mutableState.value.isEnabled) startAutoRefresh()
    }

    fun syncFromSettings(refresh: Boolean = false) {
        val loaded = loadStateFromStore()
        val updated = synchronized(requestLock) {
            val previous = mutableState.value
            val requestContextChanged =
                loaded.currencyCode != previous.currencyCode || loaded.isEnabled != previous.isEnabled
            if (requestContextChanged) requestGeneration += 1
            loaded.copy(
                isFetching = previous.isFetching && loaded.isEnabled && !requestContextChanged,
                errorMessage = previous.errorMessage.takeIf {
                    loaded.isEnabled && !requestContextChanged
                },
            ).also { mutableState.value = it }
        }
        if (enableAutoRefresh && updated.isEnabled) {
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
        val request = synchronized(requestLock) {
            val current = mutableState.value
            if (!current.isEnabled) {
                null
            } else {
                PriceRequest(
                    generation = ++requestGeneration,
                    currencyCode = current.currencyCode,
                ).also {
                    mutableState.value = current.copy(isFetching = true, errorMessage = null)
                }
            }
        } ?: return null

        val price = try {
            priceFetcher(request.currencyCode)
        } catch (error: CancellationException) {
            finishCancelledRequest(request)
            throw error
        } catch (error: Throwable) {
            publishFailure(request, error)
            return null
        }

        return synchronized(requestLock) {
            if (isCurrentRequest(request)) {
                val now = nowEpochMillis()
                settingsStore.setCachedPrice(price, request.currencyCode)
                settingsStore.setCachedPriceDate(now, request.currencyCode)
                mutableState.value = mutableState.value.copy(
                    btcPrice = price,
                    isFetching = false,
                    lastUpdatedEpochMillis = now,
                    errorMessage = null,
                )
                price
            } else {
                null
            }
        }
    }

    private fun publishFailure(request: PriceRequest, error: Throwable) {
        synchronized(requestLock) {
            if (!isCurrentRequest(request)) return
            mutableState.value = mutableState.value.copy(
                isFetching = false,
                errorMessage = error.message ?: "Could not fetch BTC price.",
            )
        }
    }

    private fun finishCancelledRequest(request: PriceRequest) {
        synchronized(requestLock) {
            if (!isCurrentRequest(request)) return
            mutableState.value = mutableState.value.copy(isFetching = false)
        }
    }

    private fun isCurrentRequest(request: PriceRequest): Boolean {
        val current = mutableState.value
        return request.generation == requestGeneration &&
            current.isEnabled &&
            current.currencyCode == request.currencyCode
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
}

private data class PriceRequest(
    val generation: Long,
    val currencyCode: String,
)

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
