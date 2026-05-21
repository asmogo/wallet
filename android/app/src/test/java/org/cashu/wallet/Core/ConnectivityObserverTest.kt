package org.cashu.wallet.Core

import org.cashu.wallet.Core.Platform.ConnectivityStatus
import org.cashu.wallet.Core.Platform.connectivityStateFromCapabilities
import org.junit.Assert.assertEquals
import org.junit.Test

class ConnectivityObserverTest {
    @Test
    fun internetCapabilityMapsToOnline() {
        val state = connectivityStateFromCapabilities(hasInternet = true, isMetered = false)

        assertEquals(ConnectivityStatus.Online, state.status)
        assertEquals("Online", state.displayText)
    }

    @Test
    fun missingInternetCapabilityMapsToOffline() {
        val state = connectivityStateFromCapabilities(hasInternet = false, isMetered = null)

        assertEquals(ConnectivityStatus.Offline, state.status)
        assertEquals("Offline", state.displayText)
    }

    @Test
    fun meteredOnlineStateIsDisplayed() {
        val state = connectivityStateFromCapabilities(hasInternet = true, isMetered = true)

        assertEquals(ConnectivityStatus.Online, state.status)
        assertEquals("Online (metered)", state.displayText)
    }
}
