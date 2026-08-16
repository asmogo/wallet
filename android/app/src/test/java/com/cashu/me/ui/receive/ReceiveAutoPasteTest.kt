package com.cashu.me.ui.receive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReceiveAutoPasteTest {
    @Test
    fun enabledSettingAcceptsOnlyCashuTokens() {
        assertEquals(
            "cashuA-token",
            automaticReceiveClipboardToken(
                enabled = true,
                currentInput = "",
                prefilledPayload = null,
                clipboardText = { "cashu:cashuA-token" },
            ),
        )
        assertNull(
            automaticReceiveClipboardToken(
                enabled = true,
                currentInput = "",
                prefilledPayload = null,
                clipboardText = { "lightning:lnbc1invoice" },
            ),
        )
    }

    @Test
    fun automaticPasteDoesNotReplaceExplicitInput() {
        assertNull(
            automaticReceiveClipboardToken(
                enabled = true,
                currentInput = "cashuB-existing",
                prefilledPayload = null,
                clipboardText = { "cashuA-clipboard" },
            ),
        )
        assertNull(
            automaticReceiveClipboardToken(
                enabled = true,
                currentInput = "",
                prefilledPayload = "cashuB-deep-link",
                clipboardText = { "cashuA-clipboard" },
            ),
        )
        var clipboardRead = false
        assertNull(
            automaticReceiveClipboardToken(
                enabled = false,
                currentInput = "",
                prefilledPayload = null,
                clipboardText = {
                    clipboardRead = true
                    "cashuA-clipboard"
                },
            ),
        )
        assertEquals(false, clipboardRead)
    }

    /**
     * Only a confirmed-spent clipboard token suppresses the auto-paste (and
     * thereby the auto-route to the claim page). When the NUT-07 check can't
     * run — offline, unreachable mint, undecodable token — the token is pasted
     * anyway and the claim page surfaces its own error.
     */
    @Test
    fun onlyConfirmedSpentClipboardTokenSkipsAutoPaste() {
        assertEquals(false, shouldAutoPasteClipboardToken(spent = true))
        assertEquals(true, shouldAutoPasteClipboardToken(spent = false))
        assertEquals(true, shouldAutoPasteClipboardToken(spent = null))
    }
}
