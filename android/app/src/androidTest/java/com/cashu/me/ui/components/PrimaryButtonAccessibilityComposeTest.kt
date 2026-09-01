package com.cashu.me.ui.components

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PrimaryButtonAccessibilityComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun loadingButtonRetainsActionNameAndProgressState() {
        compose.setCashuContent {
            PrimaryButton(
                text = "Pay",
                onClick = {},
                loading = true,
            )
        }

        val semantics = compose.onNodeWithContentDescription("Pay")
            .fetchSemanticsNode()
            .config

        assertEquals(Role.Button, semantics[SemanticsProperties.Role])
        assertEquals("In progress", semantics[SemanticsProperties.StateDescription])
    }
}
