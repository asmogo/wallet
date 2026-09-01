package com.cashu.me.Core

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PriceServiceTest {
    @Test
    fun staleUsdResponseCannotOverwriteNewerEurPrice() = runBlocking {
        val settings = FakePriceSettings(priceEnabled = true, priceCurrencyCode = "USD")
        val fetcher = ControlledPriceFetcher()
        val service = PriceService(
            settingsStore = settings,
            priceFetcher = fetcher::fetch,
            nowEpochMillis = { 1_234L },
            enableAutoRefresh = false,
        )

        val usdRequest = async { service.refreshBitcoinPrice() }
        assertEquals("USD", fetcher.started.receive())
        settings.priceCurrencyCode = "EUR"
        val eurRequest = async { service.refreshBitcoinPrice() }
        assertEquals("EUR", fetcher.started.receive())

        fetcher.complete("EUR", 90_000.0)
        assertEquals(90_000.0, requireNotNull(eurRequest.await()), 0.0)
        fetcher.complete("USD", 100_000.0)
        assertNull(usdRequest.await())

        assertEquals("EUR", service.state.value.currencyCode)
        assertEquals(90_000.0, service.state.value.btcPrice, 0.0)
        assertEquals(1_234L, service.state.value.lastUpdatedEpochMillis)
        assertEquals(90_000.0, settings.cachedPrice("EUR") ?: 0.0, 0.0)
        assertNull(settings.cachedPrice("USD"))
        assertFalse(service.state.value.isFetching)
    }

    @Test
    fun responseIsIgnoredAfterPricesAreDisabled() = runBlocking {
        val settings = FakePriceSettings(priceEnabled = true, priceCurrencyCode = "USD")
        val fetcher = ControlledPriceFetcher()
        val service = PriceService(
            settingsStore = settings,
            priceFetcher = fetcher::fetch,
            enableAutoRefresh = false,
        )

        val request = async { service.refreshBitcoinPrice() }
        assertEquals("USD", fetcher.started.receive())
        settings.priceEnabled = false
        service.syncFromSettings()

        assertFalse(service.state.value.isEnabled)
        assertFalse(service.state.value.isFetching)
        fetcher.complete("USD", 100_000.0)
        assertNull(request.await())

        assertFalse(service.state.value.isEnabled)
        assertEquals(0.0, service.state.value.btcPrice, 0.0)
        assertNull(settings.cachedPrice("USD"))
    }

    @Test
    fun cancellingRefreshRemainsCancellationAndClearsFetchingState() = runBlocking {
        val settings = FakePriceSettings(priceEnabled = true, priceCurrencyCode = "USD")
        val started = CompletableDeferred<Unit>()
        val service = PriceService(
            settingsStore = settings,
            priceFetcher = {
                started.complete(Unit)
                awaitCancellation()
            },
            enableAutoRefresh = false,
        )

        val request = async { service.refreshBitcoinPrice() }
        started.await()
        request.cancel()
        request.join()

        assertTrue(request.isCancelled)
        assertFalse(service.state.value.isFetching)
        assertNull(service.state.value.errorMessage)
    }

    private class ControlledPriceFetcher {
        val started = Channel<String>(Channel.UNLIMITED)
        private val responses = ConcurrentHashMap<String, CompletableDeferred<Double>>()

        suspend fun fetch(currency: String): Double {
            started.send(currency)
            return responses.getOrPut(currency) { CompletableDeferred() }.await()
        }

        fun complete(currency: String, price: Double) {
            responses.getOrPut(currency) { CompletableDeferred() }.complete(price)
        }
    }

    private class FakePriceSettings(
        override var priceEnabled: Boolean,
        override var priceCurrencyCode: String,
    ) : PriceSettingsStore {
        override var showFiatBalance: Boolean = false
        override var bitcoinPriceCurrency: String = priceCurrencyCode
        private val prices = mutableMapOf<String, Double>()
        private val dates = mutableMapOf<String, Long>()

        override fun cachedPrice(currency: String): Double? = prices[currency]

        override fun setCachedPrice(price: Double, currency: String) {
            prices[currency] = price
        }

        override fun cachedPriceDate(currency: String): Long? = dates[currency]

        override fun setCachedPriceDate(epochMillis: Long, currency: String) {
            dates[currency] = epochMillis
        }
    }
}
