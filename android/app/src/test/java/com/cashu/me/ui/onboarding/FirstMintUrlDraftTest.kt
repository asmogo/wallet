package com.cashu.me.ui.onboarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FirstMintUrlDraftTest {
    @Test
    fun validUrlIsNormalizedAndStaged() {
        val result = FirstMintUrlDraft(" 'mint.example.com/path/' ").stage(emptyList())

        assertEquals("https://mint.example.com/path", result.stagedUrl)
        assertEquals(FirstMintUrlDraft(), result.draft)
    }

    @Test
    fun malformedHostIsRejectedWithoutStaging() {
        val result = FirstMintUrlDraft("https:///missing-host").stage(emptyList())

        assertNull(result.stagedUrl)
        assertEquals(InvalidFirstMintUrlMessage, result.draft.error)
        assertEquals("https:///missing-host", result.draft.input)
    }

    @Test
    fun normalizedDuplicateIsRejectedWithoutStaging() {
        val result = FirstMintUrlDraft("MINT.EXAMPLE.COM/").stage(
            existingUrls = listOf("https://mint.example.com"),
        )

        assertNull(result.stagedUrl)
        assertEquals("That mint is already in the list.", result.draft.error)
    }

    @Test
    fun validationErrorRemainsUntilInputActuallyChanges() {
        val rejected = FirstMintUrlDraft("not a url").stage(emptyList()).draft

        assertEquals(InvalidFirstMintUrlMessage, rejected.error)
        assertEquals(InvalidFirstMintUrlMessage, rejected.updateInput("not a url").error)
        assertNull(rejected.updateInput("mint.example.com").error)
    }
}
