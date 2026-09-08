package com.cashu.me.ui.history

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FixtureMode
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HistoryFilterAccessibilityTest {
    @get:Rule val compose = createEmptyComposeRule()
    @Test fun filterAnnouncesEverySelection() {
        AppTestFixture.launch(FixtureMode.SeededWithoutMint).use {
            WalletJourneyRobot(compose).awaitTag(UiTestTags.WalletScreen).tapText("History")
            val control = compose.onNodeWithContentDescription("Filter transactions")
            control.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "All"))
            for ((label, spoken) in listOf("Pending" to "Pending only", "Completed" to "Completed only", "All" to "All")) {
                control.performClick()
                compose.onNodeWithText(label).performClick()
                control.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, spoken))
            }
        }
    }
}
