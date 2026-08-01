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

@RunWith(AndroidJUnit4::class)
class NostrPrivateKeyWarningComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun warningExplainsIdentityAndLightningAddressRiskAccessibly() {
        compose.setCashuContent {
            NostrPrivateKeyWarning()
        }

        val warning = compose.onNodeWithText(NostrPrivateKeyWarningText)
            .assertIsDisplayed()
            .fetchSemanticsNode()

        assertEquals(
            listOf(NostrPrivateKeyWarningText),
            warning.config[SemanticsProperties.Text].map { it.text },
        )
    }
}
