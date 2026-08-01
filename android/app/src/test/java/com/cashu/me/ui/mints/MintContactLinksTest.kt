package com.cashu.me.ui.mints

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Mint-reported contacts and external links only become tappable when they
 * parse into the mailto:/http(s) allowlist (iOS `contactURL`, hardened).
 */
class MintContactLinksTest {

    @Test
    fun emailBuildsMailtoForPlausibleAddresses() {
        assertEquals("mailto:support@mint.example", mintContactLink("email", "support@mint.example"))
        assertEquals("mailto:support@mint.example", mintContactLink("Email", "  support@mint.example  "))
    }

    @Test
    fun emailWithoutAddressShapeIsNotTappable() {
        assertNull(mintContactLink("email", "not-an-address"))
        assertNull(mintContactLink("email", "two @ addresses"))
        assertNull(mintContactLink("email", ""))
    }

    @Test
    fun websiteGainsHttpsSchemeWhenMissing() {
        assertEquals("https://mint.example", mintContactLink("website", "mint.example"))
        assertEquals("https://mint.example/about", mintContactLink("url", "https://mint.example/about"))
        assertEquals("http://mint.example", mintContactLink("web", "http://mint.example"))
    }

    @Test
    fun twitterAndTelegramHandlesBecomeProfileLinks() {
        assertEquals("https://twitter.com/mint", mintContactLink("twitter", "@mint"))
        assertEquals("https://twitter.com/mint", mintContactLink("x", "mint"))
        assertEquals("https://t.me/mint", mintContactLink("telegram", "@mint"))
        assertEquals("https://t.me/s/mint", mintContactLink("telegram", "https://t.me/s/mint"))
    }

    @Test
    fun nostrAndUnknownMethodsStayTextUnlessTheyAreUrls() {
        assertNull(mintContactLink("nostr", "npub1abc"))
        assertEquals("https://mint.example", mintContactLink("nostr", "https://mint.example"))
    }

    @Test
    fun unsafeSchemesAreRejected() {
        assertNull(mintContactLink("website", "javascript:alert(1)"))
        assertNull(mintContactLink("website", "intent://scan"))
        assertNull(mintContactLink("website", "file:///etc/passwd"))
        assertNull(mintContactLink("website", "https://"))
    }

    @Test
    fun termsOfServiceUrlMustBeHttpWithAHost() {
        assertEquals("https://mint.example/tos", safeExternalHttpUrl(" https://mint.example/tos "))
        assertNull(safeExternalHttpUrl(null))
        assertNull(safeExternalHttpUrl(""))
        assertNull(safeExternalHttpUrl("not a url"))
        assertNull(safeExternalHttpUrl("ftp://mint.example/tos"))
        assertNull(safeExternalHttpUrl("https://"))
    }

    @Test
    fun hostExtractionLabelsTheDestination() {
        assertEquals("mint.example", externalUrlHost("https://mint.example/tos?x=1"))
        assertNull(externalUrlHost("not a url"))
    }
}
