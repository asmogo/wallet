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
                clipboardText = "cashu:cashuA-token",
            ),
        )
        assertNull(
            automaticReceiveClipboardToken(
                enabled = true,
                currentInput = "",
                prefilledPayload = null,
                clipboardText = "lightning:lnbc1invoice",
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
                clipboardText = "cashuA-clipboard",
            ),
        )
        assertNull(
            automaticReceiveClipboardToken(
                enabled = true,
                currentInput = "",
                prefilledPayload = "cashuB-deep-link",
                clipboardText = "cashuA-clipboard",
            ),
        )
        assertNull(
            automaticReceiveClipboardToken(
                enabled = false,
                currentInput = "",
                prefilledPayload = null,
                clipboardText = "cashuA-clipboard",
            ),
        )
    }
}
