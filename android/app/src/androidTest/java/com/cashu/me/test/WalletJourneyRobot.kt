package com.cashu.me.test

import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.espresso.Espresso.pressBack

class WalletJourneyRobot(
    private val compose: ComposeTestRule,
) {
    fun awaitTag(tag: String, timeoutMillis: Long = DefaultTimeout): WalletJourneyRobot {
        compose.waitUntil(timeoutMillis) {
            compose.onAllNodes(hasTestTag(tag), useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
        compose.onNodeWithTag(tag, useUnmergedTree = true).assertIsDisplayed()
        return this
    }

    fun awaitText(
        text: String,
        substring: Boolean = false,
        timeoutMillis: Long = DefaultTimeout,
    ): WalletJourneyRobot {
        val matcher = hasText(text, substring = substring)
        await(matcher, timeoutMillis)
        compose.onNode(matcher, useUnmergedTree = true).assertIsDisplayed()
        return this
    }

    fun awaitDescription(
        description: String,
        timeoutMillis: Long = DefaultTimeout,
    ): WalletJourneyRobot {
        val matcher = hasContentDescription(description)
        await(matcher, timeoutMillis)
        compose.onNodeWithContentDescription(description, useUnmergedTree = true).assertIsDisplayed()
        return this
    }

    fun tapTag(tag: String): WalletJourneyRobot {
        awaitTag(tag)
        compose.onNodeWithTag(tag, useUnmergedTree = true).performClick()
        return this
    }

    fun tapText(text: String, substring: Boolean = false): WalletJourneyRobot {
        awaitText(text, substring)
        compose.onNodeWithText(
            text,
            substring = substring,
            useUnmergedTree = true,
        ).performClick()
        return this
    }

    fun tapTextWithinTag(
        parentTag: String,
        text: String,
        substring: Boolean = false,
    ): WalletJourneyRobot {
        val matcher = hasText(text, substring = substring)
            .and(hasAnyAncestor(hasTestTag(parentTag)))
        await(matcher, DefaultTimeout)
        compose.onNode(matcher, useUnmergedTree = true).performClick()
        return this
    }

    fun awaitTextWithinTag(
        parentTag: String,
        text: String,
        substring: Boolean = false,
    ): WalletJourneyRobot {
        val matcher = hasText(text, substring = substring)
            .and(hasAnyAncestor(hasTestTag(parentTag)))
        await(matcher, DefaultTimeout)
        compose.onNode(matcher, useUnmergedTree = true).assertIsDisplayed()
        return this
    }

    fun scrollToText(containerTag: String, text: String): WalletJourneyRobot {
        compose.onNodeWithTag(containerTag, useUnmergedTree = true)
            .performScrollToNode(hasText(text))
        return this
    }

    fun tapDescription(description: String): WalletJourneyRobot {
        awaitDescription(description)
        compose.onNodeWithContentDescription(
            description,
            useUnmergedTree = true,
        ).performClick()
        return this
    }

    fun typeIntoTag(tag: String, value: String): WalletJourneyRobot {
        awaitTag(tag)
        compose.onNodeWithTag(tag, useUnmergedTree = true).performTextInput(value)
        return this
    }

    fun replaceTextInTag(tag: String, value: String): WalletJourneyRobot {
        awaitTag(tag)
        compose.onNodeWithTag(tag, useUnmergedTree = true).performTextReplacement(value)
        return this
    }

    fun pressSystemBack(): WalletJourneyRobot {
        pressBack()
        compose.waitForIdle()
        return this
    }

    fun assertTagDoesNotExist(tag: String): WalletJourneyRobot {
        compose.waitUntil(DefaultTimeout) {
            compose.onAllNodes(hasTestTag(tag), useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isEmpty()
        }
        return this
    }

    fun assertTagIsNotEnabled(tag: String): WalletJourneyRobot {
        awaitTag(tag)
        compose.onNodeWithTag(tag, useUnmergedTree = true).assertIsNotEnabled()
        return this
    }

    fun assertTextDoesNotExist(
        text: String,
        substring: Boolean = false,
        timeoutMillis: Long = DefaultTimeout,
    ): WalletJourneyRobot {
        val matcher = hasText(text, substring = substring)
        compose.waitUntil(timeoutMillis) {
            compose.onAllNodes(matcher, useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isEmpty()
        }
        return this
    }

    fun completeCreateWalletToFirstMint(): WalletJourneyRobot {
        awaitTag(com.cashu.me.ui.testing.UiTestTags.OnboardingRoot)
            .tapTag(com.cashu.me.ui.testing.UiTestTags.CreateWallet)
            .awaitText("Your Seed", substring = true)
            .tapTag(com.cashu.me.ui.testing.UiTestTags.RevealSeed)
            .awaitTag(com.cashu.me.ui.testing.UiTestTags.SeedPhrase)
            .tapTag(com.cashu.me.ui.testing.UiTestTags.AcknowledgeSeed)
            .tapTag(com.cashu.me.ui.testing.UiTestTags.SeedSaved)
            .awaitText("Pick your", substring = true)
        return this
    }

    private fun await(matcher: SemanticsMatcher, timeoutMillis: Long) {
        compose.waitUntil(timeoutMillis) {
            compose.onAllNodes(matcher, useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
    }

    companion object {
        const val DefaultTimeout = 12_000L
    }
}
