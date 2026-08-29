package com.cashu.me.ui.settings

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The nsec warning now travels with the reveal sheet instead of standing
 * permanently on the Nostr screen, so it lands at the moment the key is about to
 * be exposed. It still has to reach assistive technology as a single node.
 */
@RunWith(AndroidJUnit4::class)
class NostrPrivateKeyWarningComposeTest {
    @get:Rule
    val compose = createComposeRule()

    private fun setRevealContent() {
        compose.setCashuContent {
            PrivateKeyRevealContent(
                title = "Nostr private key",
                warning = NostrPrivateKeyWarningText,
                revealedNsec = null,
                onReveal = {},
                onCopy = {},
            )
        }
    }

    @Test
    fun warningExplainsIdentityAndLightningAddressRiskAccessibly() {
        setRevealContent()

        val warning = compose.onNodeWithText(NostrPrivateKeyWarningText)
            .assertIsDisplayed()
            .fetchSemanticsNode()

        assertEquals(
            listOf(NostrPrivateKeyWarningText),
            warning.config[SemanticsProperties.Text].map { it.text },
        )
    }

    @Test
    fun revealSheetNamesWhichKeyItIsAboutToShow() {
        setRevealContent()

        compose.onNodeWithText("Nostr private key").assertIsDisplayed()
    }
}
