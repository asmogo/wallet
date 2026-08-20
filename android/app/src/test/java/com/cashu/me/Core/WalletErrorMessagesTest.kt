package com.cashu.me.Core

import com.cashu.me.Core.Wallet.WalletErrorMessages
import com.cashu.me.Core.Wallet.WalletMessageSeverity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** iOS parity: `WalletErrorMessageTests.swift`. */
class WalletErrorMessagesTest {

    private val mintLimitsCopy =
        "This amount is outside the mint's limits. Try a different amount."

    /**
     * A NUT-04/05 amount rejection must never reach the UI as CDK's own text.
     * The mint returns code 11006 with the real bounds in `detail`, but decoding
     * that response back into an Error rebuilds the variant with three
     * `Amount::default()` — so CDK renders "Amount must be between `0` and `0`
     * is `0`" for every mint at every amount. Regression guard for the copy the
     * user saw shipped verbatim.
     */
    @Test
    fun `cdk amount limit wording maps to mint limits copy`() {
        val message = WalletErrorMessages.classifyMessage("Amount must be between `0` and `0` is `0`")

        assertEquals(mintLimitsCopy, message.text)
        assertEquals(WalletMessageSeverity.Caution, message.severity)
    }

    /**
     * The same rule still has to catch the phrasings it was originally written
     * for, so adding CDK's wording can't quietly narrow it.
     */
    @Test
    fun `legacy amount limit wordings still map to mint limits copy`() {
        listOf(
            "Amount out of range",
            "Amount is outside of allowed range",
            "amount is outside the allowed limits",
        ).forEach { raw ->
            assertEquals(raw, mintLimitsCopy, WalletErrorMessages.classifyMessage(raw).text)
        }
    }

    /**
     * `TransactionUnbalanced` is rebuilt as `(0, 0, 0)` by the same decoder, so it
     * reaches us as "Inputs: `0`, Outputs: `0`, Expected Fee: `0`" — three more
     * meaningless numbers that must not be shown.
     */
    @Test
    fun `cdk unbalanced wording maps to fee disagreement copy`() {
        val message =
            WalletErrorMessages.classifyMessage("Inputs: `0`, Outputs: `0`, Expected Fee: `0`")

        assertEquals(
            "The wallet and mint disagreed on the fee. Try again or use another mint.",
            message.text,
        )
        assertFalse(message.text.contains("`0`"))
    }

    /**
     * The zeroed CDK string must not survive anywhere in the resolved copy —
     * the whole point of the mapping is that those numbers are meaningless.
     */
    @Test
    fun `resolved copy never leaks the zeroed bounds`() {
        val text = WalletErrorMessages.classifyMessage("Amount must be between `0` and `0` is `0`").text

        assertFalse(text.contains("`0`"))
        assertFalse(text.lowercase().contains("must be between"))
    }
}
