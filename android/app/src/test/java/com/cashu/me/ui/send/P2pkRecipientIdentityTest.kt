package com.cashu.me.ui.send

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class P2pkRecipientIdentityTest {
    private val xOnlyKey = "a".repeat(64)

    @Test
    fun primaryCompressedKeyIsRecognizedAsOwnRecipient() {
        assertTrue(
            isOwnP2pkRecipient(
                recipient = "02$xOnlyKey",
                ownPublicKeys = listOf("02$xOnlyKey"),
            ),
        )
    }

    @Test
    fun storedXOnlyKeyIsRecognizedAsOwnRecipient() {
        assertTrue(
            isOwnP2pkRecipient(
                recipient = "03$xOnlyKey",
                ownPublicKeys = listOf(xOnlyKey),
            ),
        )
    }

    @Test
    fun externalKeyIsNotMarkedAsOwnRecipient() {
        assertFalse(
            isOwnP2pkRecipient(
                recipient = "02${"b".repeat(64)}",
                ownPublicKeys = listOf("02$xOnlyKey", "c".repeat(64)),
            ),
        )
    }
}
