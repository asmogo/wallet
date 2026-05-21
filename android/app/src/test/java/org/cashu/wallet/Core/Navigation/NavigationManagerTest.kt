package org.cashu.wallet.Core.Navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NavigationManagerTest {
    @Test
    fun cashuTokenDeepLinkRoutesToReceive() {
        val result = NavigationManager.routeForDeepLink("cashu:cashuA-test-token")

        assertEquals(CashuRoute.Receive, result?.route)
        assertEquals("cashuA-test-token", result?.payload)
    }

    @Test
    fun cashuSlashedTokenDeepLinkRoutesToReceive() {
        val result = NavigationManager.routeForDeepLink("cashu://cashuB-test-token")

        assertEquals(CashuRoute.Receive, result?.route)
        assertEquals("cashuB-test-token", result?.payload)
    }

    @Test
    fun percentEncodedCashuDeepLinkIsDecoded() {
        val result = NavigationManager.routeForDeepLink("cashu:cashuA%2Dtest%2Dtoken")

        assertEquals(CashuRoute.Receive, result?.route)
        assertEquals("cashuA-test-token", result?.payload)
    }

    @Test
    fun cashuPaymentRequestDeepLinkRoutesToSend() {
        val result = NavigationManager.routeForDeepLink("cashu:creqa-test-request")

        assertEquals(CashuRoute.Send, result?.route)
        assertEquals("creqa-test-request", result?.payload)
    }

    @Test
    fun invalidCashuDeepLinkIsIgnored() {
        assertNull(NavigationManager.routeForDeepLink("cashu:not-a-supported-payload"))
    }
}
