package com.cashu.me.Core

import com.cashu.me.Core.Wallet.ActionErrorMessages
import com.cashu.me.Core.Wallet.ActionErrorMessages.Context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ActionErrorMessagesTest {
    @Test
    fun lightningDnsFailureNamesTheServiceWithoutExposingTheException() {
        val raw = IllegalStateException("errorMessage=HTTP request failed: failed to lookup address information: No address associated with hostname")
        assertEquals(
            "Couldn't connect to the Lightning address service. Try again shortly.",
            ActionErrorMessages.message(raw, Context.LightningConnection),
        )
        assertEquals(
            "Couldn't check for Lightning payments. Try again shortly.",
            ActionErrorMessages.message(raw, Context.LightningPayments),
        )
    }

    @Test
    fun unknownFailuresNeverExposeCredentialsOrStorageDetails() {
        Context.entries.forEach { context ->
            val message = ActionErrorMessages.message(
                IllegalStateException("errorMessage=failed at internal/path with nsec1private https://user:secret@example.test"),
                context,
            )
            listOf("errorMessage", "internal/path", "nsec1private", "https://", "secret").forEach {
                assertFalse(message, message.contains(it))
            }
        }
    }

    @Test
    fun importRetainsUsefulValidationAndDuplicateKeyGuidance() {
        assertEquals(
            "That private key doesn't look right. Check that you copied the complete nsec key.",
            ActionErrorMessages.message(IllegalArgumentException("Invalid nsec format"), Context.KeyImport),
        )
        assertEquals(
            "This key is already in your wallet.",
            ActionErrorMessages.message(IllegalArgumentException("Key already exists"), Context.KeyImport),
        )
        assertEquals(
            "Couldn't import this key. Check it and try again.",
            ActionErrorMessages.message(IllegalStateException("Failed to save encrypted nsec"), Context.KeyImport),
        )
        assertEquals(
            "Couldn't remove this key. Try again.",
            ActionErrorMessages.message(IllegalStateException("Invalid nsec metadata"), Context.KeyRemove),
        )
    }
    @Test
    fun secureStorageFailureDoesNotExposeInternalDetails() {
        assertEquals(
            "Couldn't access the wallet's secure storage. Restart the app and try again.",
            com.cashu.me.Core.Wallet.WalletErrorMessages.classifyMessage("Keystore error at internal/path (status: -34018)").text,
        )
    }

}
