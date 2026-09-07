package com.cashu.me.ui.components

import androidx.compose.ui.semantics.Role
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
class DestructiveTextButtonAccessibilityComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun destructiveActionExposesButtonRoleAndAccessibleWarning() {
        compose.setCashuContent {
            DestructiveTextButton(
                context = TextButtonContext.Compact,
                text = "Generate",
                onClick = {},
            )
        }

        val semantics = compose.onNodeWithText("Generate")
            .assertIsDisplayed()
            .fetchSemanticsNode()
            .config

        assertEquals(Role.Button, semantics[SemanticsProperties.Role])
        assertEquals(
            "Destructive action",
            semantics[SemanticsProperties.StateDescription],
        )
    }
}
