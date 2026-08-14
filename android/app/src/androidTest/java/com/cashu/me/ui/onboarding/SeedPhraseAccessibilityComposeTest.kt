package com.cashu.me.ui.onboarding

import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
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
        // Deliberate change (2026-08-05): the card is now a toggle, so the
        // revealed state keeps exactly one click action — "Hide seed phrase" —
        // where it previously had none. The contract that still matters is that
        // the masked state exposes one and only one control (asserted above in
        // `hiddenPhraseExposesOnlyOneRevealAction`), and that revealing does not
        // bury the words: the click action sits on the container WITHOUT
        // `clearAndSetSemantics`, so the 12 ordered words remain traversable —
        // which the assertion at the end of this test proves.
        compose.onAllNodes(hasClickAction()).assertCountEquals(1)
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

    /**
     * Backing out of the seed step and coming back in must present the phrase
     * hidden again — a revealed seed left over from an earlier visit defeats the
     * deliberate reveal. The stage owns `revealed` as `remember` state, so this
     * pins the composition-lifecycle reset the behaviour depends on. iOS has to
     * clear the flag by hand (`showMnemonicStage.onAppear`) because there the
     * state lives on the onboarding root.
     */
    @Test
    fun reenteringTheStageHidesThePhraseAgain() {
        val onStage = mutableStateOf(true)
        compose.setCashuContent {
            if (onStage.value) {
                ShowMnemonicStageContent(mnemonic = words.joinToString(" "), onBack = {})
            } else {
                Text("welcome")
            }
        }

        compose.onNodeWithContentDescription("Reveal seed phrase").performClick()
        compose.onNodeWithTag(UiTestTags.SeedPhrase).assertIsDisplayed()

        // Back to Welcome, then Create Wallet again — the reported journey.
        compose.runOnIdle { onStage.value = false }
        compose.onNodeWithText("welcome").assertIsDisplayed()
        compose.runOnIdle { onStage.value = true }

        compose.onNodeWithContentDescription("Reveal seed phrase").assertIsDisplayed()
        // The hidden grid's tag lives under `clearAndSetSemantics`, so it is
        // merged away in the default tree — the whole point of the masking.
        compose.onNodeWithTag(UiTestTags.HiddenSeedPhrase, useUnmergedTree = true).assertExists()
        compose.onNodeWithTag(UiTestTags.SeedPhrase).assertDoesNotExist()
    }

    /** Tapping a revealed card puts the phrase away again. */
    @Test
    fun tappingARevealedPhraseHidesItAgain() {
        setSeedPhraseContent()

        compose.onNodeWithContentDescription("Reveal seed phrase").performClick()
        compose.onNodeWithTag(UiTestTags.SeedPhrase).assertIsDisplayed()

        // "Hide seed phrase" is the click action's *label*, not a content
        // description: the revealed card must not describe itself, or TalkBack
        // would announce the container instead of letting you read the words.
        // There is exactly one clickable node in the revealed state (asserted
        // in `revealReplacesActionWithOrderedNumberedWords`), so match on that.
        val hide = compose.onNode(hasClickAction())
        hide.assert(
            SemanticsMatcher("onClick label is 'Hide seed phrase'") { node ->
                node.config.getOrNull(SemanticsActions.OnClick)?.label == "Hide seed phrase"
            },
        )
        hide.performClick()

        compose.onNodeWithContentDescription("Reveal seed phrase").assertIsDisplayed()
        compose.onNodeWithTag(UiTestTags.SeedPhrase).assertDoesNotExist()
        words.forEach { word -> compose.onNodeWithText(word).assertDoesNotExist() }
    }

    private fun setSeedPhraseContent() {
        compose.setCashuContent {
            var revealed by remember { mutableStateOf(false) }
            SeedPhraseReveal(
                words = words,
                revealed = revealed,
                onToggle = { revealed = !revealed },
            )
        }
    }
}
