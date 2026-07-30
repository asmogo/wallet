package com.cashu.me.ui.send

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SendEcashRecipientKeyTest {
    @Test
    fun xOnlyInputIsCanonicalizedForEveryInputSource() {
        val xOnly = "A".repeat(64)
        val inputs = listOf(
            xOnly, // typed
            " $xOnly\n", // pasted
            xOnly.lowercase(), // scanned
        )

        val validations = inputs.map(::validateP2PKRecipientKey)

        assertEquals(1, validations.map { it.normalizedKey }.distinct().size)
        assertEquals("02${xOnly.lowercase()}", validations.first().normalizedKey)
        validations.forEach { assertNull(it.errorMessage) }
    }

    @Test
    fun invalidInputUsesTheSameErrorForEveryInputSource() {
        val invalid = "04${"b".repeat(64)}"

        val validations = listOf(invalid, " $invalid ", invalid.uppercase())
            .map(::validateP2PKRecipientKey)

        validations.forEach { assertNull(it.normalizedKey) }
        assertEquals(1, validations.map { it.errorMessage }.distinct().size)
        assertEquals(
            "Invalid P2PK pubkey. Use a 66-character hex key with 02/03 prefix.",
            validations.first().errorMessage,
        )
    }

    @Test
    fun blankInputIsAwaitingARecipientRatherThanInvalid() {
        val validation = validateP2PKRecipientKey(" \n ")

        assertNull(validation.normalizedKey)
        assertNull(validation.errorMessage)
    }
}
