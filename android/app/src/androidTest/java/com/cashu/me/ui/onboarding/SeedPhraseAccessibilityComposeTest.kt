package com.cashu.me.ui.onboarding

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SeedPhraseAccessibilityComposeTest {
    @get:Rule
    val compose = createComposeRule()

    private val words = listOf(
        "abandon",
        "ability",
        "able",
        "about",
        "above",
        "absent",
        "absorb",
        "abstract",
        "absurd",
        "abuse",
        "access",
        "accident",
    )

    @Test
    fun hiddenPhraseExposesOnlyOneRevealAction() {
        setSeedPhraseContent()

        compose.onAllNodes(
            hasContentDescription("Reveal seed phrase"),
        ).assertCountEquals(1)
        compose.onAllNodes(hasClickAction()).assertCountEquals(1)
        compose.onNodeWithContentDescription(
            "Reveal seed phrase",
        )
            .assertIsDisplayed()
            .assertHasClickAction()

        words.forEach { word ->
            compose.onNodeWithText(word).assertDoesNotExist()
        }
        compose.onNodeWithText("01").assertDoesNotExist()
        compose.onNodeWithText("••••••").assertDoesNotExist()
    }

    @Test
    fun revealReplacesActionWithOrderedNumberedWords() {
        setSeedPhraseContent()

        compose.onNodeWithContentDescription(
            "Reveal seed phrase",
        ).performClick()

        compose.onNodeWithContentDescription(
            "Reveal seed phrase",
        ).assertDoesNotExist()
        compose.onAllNodes(hasClickAction()).assertCountEquals(0)
        compose.onNodeWithTag(
            UiTestTags.SeedPhrase,
        ).assertIsDisplayed()

        val expectedLabels = words.mapIndexed { index, word -> "${index + 1}. $word" }
        val expectedLabelSet = expectedLabels.toSet()
        val wordNodeMatcher = SemanticsMatcher("numbered seed word") { node ->
            node.config
                .getOrNull(SemanticsProperties.ContentDescription)
                ?.singleOrNull() in expectedLabelSet
        }
        val actualLabels = compose.onAllNodes(
            wordNodeMatcher,
        ).fetchSemanticsNodes().map { node ->
            node.config[SemanticsProperties.ContentDescription].single()
        }

        assertEquals(expectedLabels, actualLabels)
    }

    private fun setSeedPhraseContent() {
        compose.setCashuContent {
            var revealed by remember { mutableStateOf(false) }
            SeedPhraseReveal(
                words = words,
                revealed = revealed,
                onReveal = { revealed = true },
            )
        }
    }
}
